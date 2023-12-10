//
//  PlayerViewController.swift
//  MetalCamera
//
//  Created by n.dubov on 12/3/23.
//

import AVFoundation
import UIKit

class PlayerViewController: UIViewController {
    private let player = AVPlayer()
    private lazy var playerLayer = AVPlayerLayer(player: player)
    private var loopObserver: Any?
    
    @IBAction private func shareButtonTapped() {
        let vc = UIActivityViewController(activityItems: [CameraService.recordingURL], applicationActivities: nil)
        present(vc, animated: true)
    }
    
    deinit {
        if let loopObserver {
            player.removeTimeObserver(loopObserver)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.layer.insertSublayer(playerLayer, at: 0)
        playerLayer.videoGravity = .resizeAspect
        loopObserver = player.addPeriodicTimeObserver(
            forInterval: .init(value: 1, timescale: 60),
            queue: .main
        ) { [weak self] time in
            guard let self, let item = player.currentItem, time >= item.duration else { return }
            self.player.pause()
            self.player.seek(to: .zero) { _ in
                self.player.play()
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer.frame = view.safeAreaLayoutGuide.layoutFrame
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard FileManager.default.fileExists(atPath: CameraService.recordingURL.path) else { return }
        let playerItem = AVPlayerItem(url: CameraService.recordingURL)
        player.replaceCurrentItem(with: playerItem)
        player.play()
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player.pause()
    }
}
