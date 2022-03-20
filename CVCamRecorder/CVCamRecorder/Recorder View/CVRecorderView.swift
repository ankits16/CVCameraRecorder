//
//  CVRecorderView.swift
//  CVCamRecorder
//
//  Created by Ankit Sachan on 20/03/22.
//

import UIKit

import AVFoundation
import ImageIO
import Photos

 protocol VideoCaptureDelegate: AnyObject {
    func videoCapture(_ capture: RecorderView, didCaptureVideoFrame: CVPixelBuffer?, timestamp: CMTime)
}

final class RecorderView: UIView {
    
    fileprivate lazy var cameraSession = AVCaptureSession()
    fileprivate lazy var videoDataOutput = AVCaptureVideoDataOutput()
    fileprivate lazy var audioDataOutput = AVCaptureAudioDataOutput()
    private var previewLayer : AVCaptureVideoPreviewLayer!
    
    
    var isUsingFrontFacingCamera : Bool = false
    
    
    //
    
    fileprivate(set) lazy var isRecording = false
    fileprivate var videoWriter: AVAssetWriter!
    fileprivate var videoWriterInput: AVAssetWriterInput!
    fileprivate var audioWriterInput: AVAssetWriterInput!
    fileprivate var sessionAtSourceTime: CMTime?
    
    
    var lastTimestamp = CMTime()
    public weak var delegate: VideoCaptureDelegate?
    public var fps = 15
    
    func setupCamera() {
        //The size of output video will be 720x1280
        cameraSession.sessionPreset = AVCaptureSession.Preset.hd1280x720
        
        //Setup your camera
        //Detect which type of camera should be used via `isUsingFrontFacingCamera`
        //        let captureDevice: AVCaptureDevice
        let devicePosition : AVCaptureDevice.Position = isUsingFrontFacingCamera ? .front : .back
        
        var captureDevice: AVCaptureDevice?
        let videoDevices = AVCaptureDevice.devices(for: AVMediaType.video)
        for device in videoDevices {
            let device = device
            if device.position == devicePosition {
                captureDevice = device
                //                setCameraConfig(camera: cameraDevice, zoomFactor: zoomFactor)
                break
            }
        }
        
        //        if isUsingFrontFacingCamera {
        //            captureDevice = AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo)
        //                .flatMap { $0 as? AVCaptureDevice }
        //                .find(where: { $0.position == .front }) ?? AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
        //        } else {
        //            captureDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
        //        }
        
        //Setup your microphone
        let audioDevice = AVCaptureDevice.default(for: AVMediaType.audio)
        //        AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeAudio)
        
        do {
            cameraSession.beginConfiguration()
            
            // Add camera to your session
            let deviceInput = try AVCaptureDeviceInput(device: captureDevice!)
            if cameraSession.canAddInput(deviceInput) {
                cameraSession.addInput(deviceInput)
            }
            
            // Add microphone to your session
            let audioInput = try AVCaptureDeviceInput(device: audioDevice!)
            if cameraSession.canAddInput(audioInput) {
                cameraSession.addInput(audioInput)
            }
            
            //Now we should define your output data
            let queue = DispatchQueue(label: "com.cvcamrecorder.record-video.data-output")
            
            //Define your video output
            videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            if cameraSession.canAddOutput(videoDataOutput) {
                videoDataOutput.setSampleBufferDelegate(self, queue: queue)
                cameraSession.addOutput(videoDataOutput)
            }
            videoDataOutput.connection(with: AVMediaType.video)?.videoOrientation = .portrait
            
            //Define your audio output
            if cameraSession.canAddOutput(audioDataOutput) {
                audioDataOutput.setSampleBufferDelegate(self, queue: queue)
                cameraSession.addOutput(audioDataOutput)
            }
            
            cameraSession.commitConfiguration()
            
            //Present the preview of video
            previewLayer = AVCaptureVideoPreviewLayer(session: cameraSession)
            previewLayer.frame = frame
            previewLayer.bounds = bounds
            previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
            //            ResizeAspectFill
            layer.addSublayer(previewLayer)
            
            //Don't forget start running your session
            //this doesn't mean start record!
            cameraSession.startRunning()
            
        }
        catch let error {
            debugPrint(error.localizedDescription)
        }
    }
    
    private var _filename = ""
    
    func setupWriter() {
        do {
            _filename = UUID().uuidString
            let videoPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("\(_filename).mp4")
            //          let url = AssetUtils.outputAssetURL(mediaType: .video)
            videoWriter = try AVAssetWriter(url: videoPath, fileType: AVFileType.mp4)
            
            //Add video input
            videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecH264,
                AVVideoWidthKey: bounds.width,
                AVVideoHeightKey: bounds.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 2300000,
                ],
            ])
            videoWriterInput.mediaTimeScale = CMTimeScale(bitPattern: 600)
            videoWriterInput.expectsMediaDataInRealTime = true
//            videoWriterInput.transform = CGAffineTransform(rotationAngle: .pi/2)
            
            videoWriterInput.expectsMediaDataInRealTime = true //Make sure we are exporting data at realtime
            if videoWriter.canAdd(videoWriterInput) {
                videoWriter.add(videoWriterInput)
            }
            
            //Add audio input
            audioWriterInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 64000,
            ])
            audioWriterInput.expectsMediaDataInRealTime = true
            if videoWriter.canAdd(audioWriterInput) {
                videoWriter.add(audioWriterInput)
            }
            
            videoWriter.startWriting() //Means ready to write down the file
        }
        catch let error {
            debugPrint(error.localizedDescription)
        }
    }
}

extension RecorderView {
    fileprivate func canWrite() -> Bool {
        return isRecording
        && videoWriter != nil
        && videoWriter.status == .writing
    }
}


extension RecorderView : AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate{
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
            
        guard output != nil,
              sampleBuffer != nil,
              connection != nil,
              CMSampleBufferDataIsReady(sampleBuffer) else { return }

        let writable = canWrite()

        if writable,
           sessionAtSourceTime == nil {
            //Start writing
            sessionAtSourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            videoWriter.startSession(atSourceTime: sessionAtSourceTime!)
        }

        if writable, output == videoDataOutput {
            //              ... //Your old code when make the overlay here
            
            if videoWriterInput.isReadyForMoreMediaData {
                //Write video buffer
                print("<<<<<<  videoWriterInput.append(")
                videoWriterInput.append(sampleBuffer)
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let deltaTime = timestamp - lastTimestamp
                if deltaTime >= CMTimeMake(value: 1, timescale: Int32(fps)) {
                    lastTimestamp = timestamp
                    let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
                    //        print("fps\(timestamp)")
                    delegate?.videoCapture(self, didCaptureVideoFrame: imageBuffer, timestamp: timestamp)
                }
            }
        } else if writable,
                  output == audioDataOutput,
                  audioWriterInput.isReadyForMoreMediaData {
            //Write audio buffer
            print("<<<<<<  audioWriterInput.append(")
            audioWriterInput.append(sampleBuffer)
        }
    }
    
}


extension RecorderView {
    func start() {
        guard !isRecording else { return }
        isRecording = true
        sessionAtSourceTime = nil
        //        startWriting()
    }
}

extension RecorderView {
  fileprivate func drawFaceMasksFor(features: [CIFaceFeature], bufferFrame: CGRect) {
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)

        //Hide all current masks
        layer.sublayers?.filter({ $0.name == "MaskFace" }).forEach { $0.isHidden = true }

        //Do nothing if no face is dected
        guard !features.isEmpty else {
            CATransaction.commit()
            return
        }

        //The problem is we detect the faces on video image size
        //but when we show on the screen which might smaller or bigger than your video size
        //so we need to re-calculate the faces bounds to fit to your screen

        let xScale = frame.width / bufferFrame.width
        let yScale = frame.height / bufferFrame.height
        let transform = CGAffineTransform(rotationAngle: .pi).translatedBy(x: -bufferFrame.width,
                                                                         y: -bufferFrame.height)

      for feature in features {
          var faceRect = feature.bounds.applying(transform)
          faceRect = CGRect(x: faceRect.minX * xScale,
                            y: faceRect.minY * yScale,
                            width: faceRect.width * xScale,
                            height: faceRect.height * yScale)
          
          //Reuse the face's layer
          var faceLayer = layer.sublayers?
                               .filter { $0.name == "MaskFace" && $0.isHidden == true }
                               .first
          if faceLayer == nil {
              //Add an image as a mask to your project with name: `face-imaged
              let faceImage = UIImage(named: "face-imaged")
              faceLayer = CALayer()
              faceLayer?.contents = faceImage?.ciImage
              faceLayer?.frame = faceRect
              faceLayer?.masksToBounds = true
              faceLayer!.contentsGravity = CALayerContentsGravity.resizeAspectFill
              layer.addSublayer(faceLayer!)
          } else {
              faceLayer?.frame = faceRect
              faceLayer?.position = faceRect.origin
              faceLayer?.isHidden = false
          }
          
          //You can add some masks for your left eye, right eye, mouth
      }
      CATransaction.commit()
  }
}




extension RecorderView {
    func stop() {
        guard isRecording else { return }
        isRecording = false
        videoWriter.finishWriting { [weak self] in
            self?.sessionAtSourceTime = nil
            guard let url = self?.videoWriter.outputURL else { return }
            self?.saveVideoToAlbum(videoUrl: url)
            let asset = AVURLAsset(url: url)
            //Do whatever you want with your asset here
        }
    }
    
    private func saveVideoToAlbum(videoUrl: URL) {
        var info = ""
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoUrl)
        }) { (success, error) in
            if success {
                info = "hello"
            } else {
                info = "保存失败，err = \(error.debugDescription)"
            }
            
            print(info)
            
            
        }
    }
}


