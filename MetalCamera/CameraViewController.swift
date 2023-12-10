//
//  ViewController.swift
//  MetalCamera
//
//  Created by n.dubov on 12/3/23.
//

import UIKit

class CameraViewController: UIViewController {
    @IBOutlet private weak var cameraView: UIView!
    private let cameraLayer: CAMetalLayer = .init()
    private lazy var cameraService = CameraService(layer: cameraLayer)
    private let shaders: [CameraService.ScaleShader] = [
        .scaleKernel,
        .scaleToFitKernel,
        .scaleToFillKernel
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        cameraView.layer.addSublayer(cameraLayer)
        try! cameraService?.initSession()
        cameraService?.activateScaleShader(shaders[0])
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraLayer.frame = cameraView.bounds
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Task { await self.cameraService?.stop() }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await self.cameraService?.start() }
    }
    
    @IBAction private func shaderSelected(_ control: UISegmentedControl) {
        cameraService?.activateScaleShader(shaders[control.selectedSegmentIndex])
    }
    
    @IBAction private func vhsButtonTapped(_ button: UIButton) {
        cameraService?.toggleVHS()
    }
    
    @IBAction private func recordButtonTapped(_ button: UIButton) {
        Task { @MainActor in
            guard let cameraService else { return }
            try! await cameraService.toggleRecording()
            button.setTitle(cameraService.isRecording ? "Stop" : "Record", for: .normal)
            if !cameraService.isRecording {
                let tabBarController = self.parent as? UITabBarController
                tabBarController?.selectedViewController = tabBarController?.viewControllers?.last
            }
        }
    }
}
