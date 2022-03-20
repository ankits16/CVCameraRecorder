//
//  ViewController.swift
//  CVCamRecorder
//
//  Created by Ankit Sachan on 20/03/22.
//

import UIKit
import CoreMedia

class ViewController: UIViewController {
    let inputWidth = 416
    let inputHeight = 416
    let maxBoundingBoxes = 10
    let labelHeight:CGFloat = 50.0
    
    var boundingBoxes = [BoundingBox]()
    var colors: [UIColor] = []
    
    let ciContext = CIContext()
    var resizedPixelBuffer: CVPixelBuffer?
    let semaphore = DispatchSemaphore(value: 2)
    
    //var yolo = YOLO4Tiny()
    var yolo = YOLO4My()
    
    @IBOutlet private weak var recoderViewContainer : UIView!
    private weak var recoderView : RecorderView!
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        Task { [weak self] in
            print("TASK IN")
            try! await self?.yolo.load(width: inputWidth, height: inputHeight, confidence: 0.4, nms: 0.6, maxBoundingBoxes: maxBoundingBoxes)
            print("TASK OUT")
        }
        setUpBoundingBoxes()
        setUpCoreImage()
    }
    
    
    @IBAction func setupRecorder(){
        if recoderView == nil{
            let recoderView = RecorderView(frame: recoderViewContainer.bounds)
            recoderViewContainer.addSubview(recoderView)
            recoderView.delegate = self
            self.recoderView = recoderView
            
            DispatchQueue.main.async {[weak self] in
                guard let  boxes = self?.boundingBoxes,let videoLayer  = self?.recoderView.layer else {return}
                for box in boxes {
                    box.addToLayer(videoLayer)
                }
                self?.semaphore.signal()
            }
            
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

extension ViewController{
    func setUpBoundingBoxes() {
        for _ in 0 ..< maxBoundingBoxes {
            boundingBoxes.append(BoundingBox())
        }
        
        // Make colors for the bounding boxes. There is one color for each class,
        // 20 classes in total.
        for r: CGFloat in [0.1,0.2, 0.3,0.4,0.5, 0.6,0.7, 0.8,0.9, 1.0] {
            for g: CGFloat in [0.3,0.5, 0.7,0.9] {
                for b: CGFloat in [0.4,0.6 ,0.8] {
                    let color = UIColor(red: r, green: g, blue: b, alpha: 1)
                    colors.append(color)
                }
            }
        }
    }
    
    func setUpCoreImage() {
        let status = CVPixelBufferCreate(nil, inputWidth, inputHeight,
                                         kCVPixelFormatType_32BGRA, nil,
                                         &resizedPixelBuffer)
        if status != kCVReturnSuccess {
            print("Error: could not create resized pixel buffer", status)
        }
    }
    
    func predict(pixelBuffer: CVPixelBuffer) {
        
        // Measure how long it takes to predict a single video frame.
        let startTime = CACurrentMediaTime()
        
        // Resize the input with Core Image.
        guard let resizedPixelBuffer = resizedPixelBuffer else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let sx = CGFloat(inputWidth) / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let sy = CGFloat(inputHeight) / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let scaleTransform = CGAffineTransform(scaleX: sx, y: sy)
        let scaledImage = ciImage.transformed(by: scaleTransform)
        ciContext.render(scaledImage, to: resizedPixelBuffer)
        
        
        if let boundingBoxes = try? yolo.predict(image: resizedPixelBuffer) {
            let elapsed = CACurrentMediaTime() - startTime
            showOnMainThread(boundingBoxes, elapsed)
        }
    }
    
    func showOnMainThread(_ boundingBoxes: [Prediction], _ elapsed: CFTimeInterval) {
        DispatchQueue.main.async { [weak self] in
            // For debugging, to make sure the resized CVPixelBuffer is correct.
            //var debugImage: CGImage?
            //VTCreateCGImageFromCVPixelBuffer(resizedPixelBuffer, nil, &debugImage)
            //self.debugImageView.image = UIImage(cgImage: debugImage!)
            
                        self?.show(predictions: boundingBoxes)
            
            //            guard  let fps = self?.measureFPS() else{return}
            //            self?.timeLabel.text = String(format: "Elapsed %.5f seconds - %.2f FPS", elapsed, fps)
            
            self?.semaphore.signal()
        }
    }
    func show(predictions: [Prediction]) {
        for i in 0..<boundingBoxes.count {
            if i < predictions.count {
                let prediction = predictions[i]
                
                let width = view.bounds.width
                let height = width * 1280 / 720
                let scaleX = width
                let scaleY = height
                let top = (view.bounds.height - height) / 2
                
                // Translate and scale the rectangle to our own coordinate system.
                var rect = prediction.rect
                rect.origin.x *= scaleX
                rect.origin.y *= scaleY
                rect.origin.y += top
                rect.size.width *= scaleX
                rect.size.height *= scaleY
                
                // Show the bounding box.
                let label = String(format: "%@ %.1f", yolo.names[prediction.classIndex] ?? "<unknown>", prediction.score)
                let color = colors[prediction.classIndex]
                boundingBoxes[i].show(frame: rect, label: label, color: color)
            } else {
                boundingBoxes[i].hide()
            }
        }
    }
}

extension ViewController : VideoCaptureDelegate{
    func videoCapture(_ capture: RecorderView, didCaptureVideoFrame pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
        if let pixelBuffer = pixelBuffer {
            DispatchQueue.global().async { [weak self] in
                print("*************  predict")
                self?.predict(pixelBuffer: pixelBuffer)
            }
        }
    }
}

