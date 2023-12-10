//
//  CameraService.swift
//  MetalCamera
//
//  Created by n.dubov on 12/8/23.
//

import AVFoundation
import Foundation

class CameraService: NSObject {
    static let recordingURL: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("recording", conformingTo: .quickTimeMovie)
    
    enum ScaleShader: String {
        case passthroughKernel
        case scaleKernel
        case scaleToFillKernel
        case scaleToFitKernel
    }
    
    private let layer: CAMetalLayer
    
    private let device: MTLDevice
    private let cmdQueue: MTLCommandQueue
    private let textureCache: CVMetalTextureCache
    private var pipelineState: MTLComputePipelineState?
    private var vhsPipelineState: MTLComputePipelineState?
    private var startVHSTime: CMTime = .zero
    
    private var assetWriter: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var writerAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var hasStartedRecordingSession: Bool = false
    private(set) var isRecording: Bool = false
    
    private let session = AVCaptureSession()
    
    init?(layer: CAMetalLayer) {
        self.layer = layer
        layer.framebufferOnly = false
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let cmdQueue = device.makeCommandQueue()
        else { return nil }
        self.device = device
        self.cmdQueue = cmdQueue
        
        var textureCache: CVMetalTextureCache?
        guard
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache) == kCVReturnSuccess,
            let textureCache
        else { return nil }
        self.textureCache = textureCache
    }
    
    func start() async {
        session.startRunning()
    }
    
    func stop() async {
        session.stopRunning()
    }
    
    func toggleRecording() async throws {
        if let assetWriter {
            isRecording = false
            hasStartedRecordingSession = false
            await assetWriter.finishWriting()
            self.assetWriter = nil
            self.writerInput = nil
            self.writerAdaptor = nil
        } else {
            if FileManager.default.fileExists(atPath: Self.recordingURL.path) {
                try FileManager.default.removeItem(at: Self.recordingURL)
            }
            let assetWriter = try AVAssetWriter(outputURL: Self.recordingURL, fileType: .mov)
            var outputSettings = AVOutputSettingsAssistant(preset: .preset1280x720)?.videoSettings
            outputSettings?[AVVideoWidthKey] = 720
            outputSettings?[AVVideoHeightKey] = 1280
            let input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: outputSettings
            )
            if assetWriter.canAdd(input) {
                assetWriter.add(input)
                self.assetWriter = assetWriter
                self.writerInput = input
                guard assetWriter.startWriting() else { return }
                hasStartedRecordingSession = false
                isRecording = true
            }
        }
    }
    
    func activateScaleShader(_ shader: ScaleShader) {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib") else { return }
        do {
            let library = try device.makeLibrary(URL: url)
            guard let function = library.makeFunction(name: shader.rawValue) else {
                fatalError("Unable to create gpu kernel")
            }
            pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    func toggleVHS() {
        guard vhsPipelineState == nil else {
            vhsPipelineState = nil
            return
        }
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib") else { return }
        do {
            let library = try device.makeLibrary(URL: url)
            guard let function = library.makeFunction(name: "vhsKernel") else {
                fatalError("Unable to create gpu kernel")
            }
            vhsPipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    func initSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        
        // Input
        guard let device = AVCaptureDevice.default(for: AVMediaType.video) else { return }
        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        // Output
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCMPixelFormat_32BGRA]
        output.setSampleBufferDelegate(self, queue: .main)
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.connection(with: .video)?.videoOrientation = .portrait
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        record(sampleBuffer)
    }
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        record(sampleBuffer)
        processAndDisplay(sampleBuffer)
    }
}

private extension CameraService {
    func record(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording else { return }
        if !hasStartedRecordingSession {
            hasStartedRecordingSession = true
            assetWriter?.startSession(atSourceTime: sampleBuffer.outputPresentationTimeStamp)
        }
        writerInput?.append(sampleBuffer)
    }
    
    func processAndDisplay(_ sampleBuffer: CMSampleBuffer) {
        guard
            let drawable = layer.nextDrawable(),
            let cmdBuffer = cmdQueue.makeCommandBuffer(),
            let pixelBuffer = sampleBuffer.imageBuffer,
            let pipelineState,
            let encoder = cmdBuffer.makeComputeCommandEncoder()
        else { return }
        
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil, .bgra8Unorm,
            CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), 0,
            &cvTexture
        )
        
        guard let cvTexture, let inputTexture = CVMetalTextureGetTexture(cvTexture) else {
            fatalError("Failed to create metal textures")
        }
        
        let outputTexture = vhsPipelineState == nil
            ? drawable.texture
            : device.makeDefaultTexture(width: drawable.texture.width, height: drawable.texture.height)
        
        encoder.encodePipeline(pipelineState, inputTexture: inputTexture, outputTexture: outputTexture)
        
        let time = sampleBuffer.outputPresentationTimeStamp
        if let vhsPipelineState {
            if startVHSTime == .zero {
                startVHSTime = time
            }
            var vhsTime = Float((time - startVHSTime).seconds)
            encoder.setBytes(&vhsTime, length: MemoryLayout.size(ofValue: vhsTime), index: 0)
            encoder.encodePipeline(vhsPipelineState, inputTexture: outputTexture, outputTexture: drawable.texture)
        } else {
            startVHSTime = .zero
        }
        
        encoder.endEncoding()
        cmdBuffer.present(drawable)
        cmdBuffer.commit()
    }
}

private extension MTLDevice {
    func makeDefaultTexture(width: Int, height: Int) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderWrite, .shaderRead]
        return makeTexture(descriptor: descriptor)!
    }
}

private extension MTLComputeCommandEncoder {
    func encodePipeline(
        _ pipelineState: MTLComputePipelineState,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture
    ) {
        setComputePipelineState(pipelineState)
        setTexture(inputTexture, index: 0)
        setTexture(outputTexture, index: 1)
        
        let w = pipelineState.threadExecutionWidth
        let h = pipelineState.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSize(width: outputTexture.width,
                                     height: outputTexture.height,
                                     depth: 1)
        dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }
}
