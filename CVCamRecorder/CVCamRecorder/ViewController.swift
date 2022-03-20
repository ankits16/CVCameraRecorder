//
//  ViewController.swift
//  CVCamRecorder
//
//  Created by Ankit Sachan on 20/03/22.
//

import UIKit

class ViewController: UIViewController {
    @IBOutlet private weak var recoderViewContainer : UIView!
    private weak var recoderView : RecorderView!
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }
    
    
    @IBAction func setupRecorder(){
        if recoderView == nil{
            let recoderView = RecorderView(frame: recoderViewContainer.bounds)
            recoderViewContainer.addSubview(recoderView)
            self.recoderView = recoderView
        }
        
        recoderView.setupCamera()
        
//        recoderView._setupCaptureSession()
    }

    @IBAction func startRecording(){
//        recoderView.toggleCapture()
        recoderView.setupWriter()
        recoderView.start()
    }
    
    @IBAction func stopRecording(){
//        recoderView.toggleCapture()
        recoderView.stop()
    }


}

