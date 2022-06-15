//
//  ViewController.swift
//  RawCam2
//
//  Created by thilina shashimal senarath on 2022-06-10.
//

import UIKit
import AVFoundation
import MetalKit
import Accelerate.vImage

class ViewController: UIViewController{
    
    let format = vImage_CGImageFormat(
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue),
        renderingIntent: .defaultIntent)!
    
    var captureSession: AVCaptureSession!
    var backCamera:AVCaptureDevice!
    var frontCamera:AVCaptureDevice!
    var backInput:AVCaptureInput!
    var frontInput:AVCaptureInput!

    var videoOutput:AVCaptureVideoDataOutput!
    var metalCommandQueue:MTLCommandQueue!
    var currentCIImage:CIImage!
    var ciContext: CIContext!
    let mtkview = MTKView()
    var metalDevice:MTLDevice!
    var takePicture = false
    var backCameraOn = true
    
    let fadeFilter = CIFilter(name: "CIPhotoEffectFade")
    let sepiaFilter = CIFilter(name: "CISepiaTone")
    let blurFilter = CIFilter(name: "CIGaussianBlur")
    let histroFilter = CIFilter(name: "CIAreaHistogram")
    let filter = GrayFilter()

    
    private let imagePreviewView:UIImageView = {
            let view = UIImageView(frame: CGRect(x: 0, y: 0, width: 70, height: 70))
            view.layer.cornerRadius = 10
            view.layer.borderWidth = 2
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            view.layer.borderColor = UIColor.white.cgColor
            return view
        }()
    private let shutterButton:UIButton = {
        let button = UIButton(frame: CGRect(x: 0, y: 0, width: 70, height: 70))
        button.layer.cornerRadius = 35
        button.layer.borderWidth = 5
        button.layer.borderColor = UIColor.white.cgColor
        button.layer.masksToBounds = true
        return button
    }()
    private let switchButton:UIButton = {
        let button = UIButton(frame: CGRect(x: 0, y: 0, width: 70, height: 70))
        let config = UIImage.SymbolConfiguration(pointSize: 50, weight: .bold, scale: .large)
        button.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera.fill",withConfiguration: config)?.withTintColor(.white), for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        return button
    }()
    private let bottomView:UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.alpha = 0.3
        return view
    }()
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        mtkview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mtkview)
        view.addSubview(shutterButton)
        view.addSubview(switchButton)
        view.addSubview(imagePreviewView)
        shutterButton.addTarget(self, action: #selector(captureImage), for: .touchUpInside)
        switchButton.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
        setupView()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        checkPermissions()
        setupMetal()
        setupCoreImage()
        setupAndStartCaptureSession()
    }
    
    func checkPermissions() {
        let cameraAuthStatus =  AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        switch cameraAuthStatus {
          case .authorized:
            return
          case .denied:
            abort()
          case .notDetermined:
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler:
            { (authorized) in
              if(!authorized){
                abort()
              }
            })
          case .restricted:
            abort()
          @unknown default:
            fatalError()
        }
    }
    
    func setupView() {
        bottomView.frame =  CGRect(x: 0, y: 0, width: self.view.frame.width, height: 100)
        bottomView.center = CGPoint(x: view.frame.width/2, y: view.frame.height-50)
        shutterButton.center = CGPoint(x: view.frame.width/2, y: view.frame.height-50)
        switchButton.center = CGPoint(x: view.frame.width-50, y: view.frame.height-50)
        imagePreviewView.translatesAutoresizingMaskIntoConstraints = false
        imagePreviewView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: CGFloat(-10)).isActive = true
        imagePreviewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: CGFloat(10)).isActive = true
        imagePreviewView.widthAnchor.constraint(equalToConstant: CGFloat(70)).isActive = true
        imagePreviewView.heightAnchor.constraint(equalToConstant: CGFloat(70)).isActive = true
        
        NSLayoutConstraint.activate([
            mtkview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mtkview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mtkview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mtkview.topAnchor.constraint(equalTo: view.topAnchor)
        ])

        
    }
    
    func setupAndStartCaptureSession(){
        DispatchQueue.global(qos: .userInitiated).async{

            self.captureSession = AVCaptureSession()

            self.captureSession.beginConfiguration()
            
            if self.captureSession.canSetSessionPreset(.photo) {
                self.captureSession.sessionPreset = .photo
            }
            self.captureSession.automaticallyConfiguresCaptureDeviceForWideColor = true
            
            self.setupInputs()
            
            self.setupOutput()
            
            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
        }
    }
    
    func setupInputs(){
        //get back camera
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            backCamera = device
        } else {
            fatalError("no back camera")
        }
        
        //get front camera
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            frontCamera = device
        } else {
            fatalError("no front camera")
        }
        
        guard let bInput = try? AVCaptureDeviceInput(device: backCamera) else {
            fatalError("could not create input device from back camera")
        }
        backInput = bInput
        if !captureSession.canAddInput(backInput) {
            fatalError("could not add back camera input to capture session")
        }
        
        guard let fInput = try? AVCaptureDeviceInput(device: frontCamera) else {
            fatalError("could not create input device from front camera")
        }
        frontInput = fInput
        if !captureSession.canAddInput(frontInput) {
            fatalError("could not add front camera input to capture session")
        }
        captureSession.addInput(backInput)
    }
    
    func setupOutput(){
        videoOutput = AVCaptureVideoDataOutput()
        let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInteractive)
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            fatalError("could not add video output")
        }
        
        videoOutput.connections.first?.videoOrientation = .portrait
    }
    
    func switchCameraInput(){
        //don't let user spam the button, fun for the user, not fun for performance
        switchButton.isUserInteractionEnabled = false
        
        //reconfigure the input
        captureSession.beginConfiguration()
        if backCameraOn {
            captureSession.removeInput(backInput)
            captureSession.addInput(frontInput)
            backCameraOn = false
        } else {
            captureSession.removeInput(frontInput)
            captureSession.addInput(backInput)
            backCameraOn = true
        }
        
        //deal with the connection again for portrait mode
        videoOutput.connections.first?.videoOrientation = .portrait
        
        //mirror video if front camera
        videoOutput.connections.first?.isVideoMirrored = !backCameraOn
        
        //commit config
        captureSession.commitConfiguration()
        
        //acitvate the camera button again
        switchButton.isUserInteractionEnabled = true
    }
    
    //MARK:- Metal
    func setupMetal(){
        metalDevice = MTLCreateSystemDefaultDevice()
        mtkview.device = metalDevice
        mtkview.isPaused = true
        mtkview.enableSetNeedsDisplay = false
        
        metalCommandQueue = metalDevice.makeCommandQueue()
        
        mtkview.delegate = self

        mtkview.framebufferOnly = false
    }
    
    func setupCoreImage(){
        ciContext = CIContext(mtlDevice: metalDevice)
        setupFilters()
    }
    
    func setupFilters(){
        sepiaFilter?.setValue(NSNumber(value: 1), forKeyPath: "inputIntensity")
        histroFilter?.setValue(NSNumber(value: 10), forKey: "inputCount")
        histroFilter?.setValue(NSNumber(value: 1.0), forKey: "inputScale")

    }
    
    func applyFilters(inputImage image: CIImage) -> CIImage? {
        var filteredImage : CIImage?
        
        //apply filters
        sepiaFilter?.setValue(image, forKeyPath: kCIInputImageKey)
        filteredImage = sepiaFilter?.outputImage
              
        fadeFilter?.setValue(image, forKeyPath: kCIInputImageKey)
        filteredImage = fadeFilter?.outputImage
        
        blurFilter?.setValue(image, forKeyPath: kCIInputImageKey)
        filteredImage = blurFilter?.outputImage
        
        return filteredImage
    }
    
    //MARK:- Actions
    @objc func captureImage(_ sender: UIButton?){
        takePicture = true
    }
    
    @objc func switchCamera(_ sender: UIButton?){
        switchCameraInput()
    }
    
    func calculateHistrogram(image: CGImage) -> [vImagePixelCount]!{

        guard
            var histogramSourceBuffer = try? vImage_Buffer(cgImage: image,
                                                           format: format)
        else {
                                                            return nil
        }
        var histogramBinZero = [vImagePixelCount](repeating: 0, count: 256)
        var histogramBinOne = [vImagePixelCount](repeating: 0, count: 256)
        var histogramBinTwo = [vImagePixelCount](repeating: 0, count: 256)
        var histogramBinThree = [vImagePixelCount](repeating: 0, count: 256)
        
        histogramBinZero.withUnsafeMutableBufferPointer { zeroPtr in
            histogramBinOne.withUnsafeMutableBufferPointer { onePtr in
                histogramBinTwo.withUnsafeMutableBufferPointer { twoPtr in
                    histogramBinThree.withUnsafeMutableBufferPointer { threePtr in

                        var histogramBins = [zeroPtr.baseAddress, onePtr.baseAddress,
                                             twoPtr.baseAddress, threePtr.baseAddress]

                        histogramBins.withUnsafeMutableBufferPointer { histogramBinsPtr in
                            let error = vImageHistogramCalculation_ARGB8888(&histogramSourceBuffer,
                                                                            histogramBinsPtr.baseAddress!,
                                                                            vImage_Flags(kvImageNoFlags))

                            guard error == kvImageNoError else {
                                fatalError("Error calculating histogram: \(error)")
                            }
                        }
                    }
                }
            }
        }
        var one = zip(histogramBinOne,histogramBinTwo).map(+)
        var two = zip(one,histogramBinThree).map(+)
        var three =  two.map{ val in return val/3}
        var histogram = [vImagePixelCount](repeating: 0, count: 10)
        let range = 256/10
        for i in 0...9{
            var val =  three[(i*range)...((i+1)*range)].reduce(0,+)
            histogram[i] = val/10
        }
        return histogram
    
    }


}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        guard let cvBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let ciImage = CIImage(cvImageBuffer: cvBuffer)

        filter.inputImage = ciImage
        guard let filteredCIImage = filter.outputImage else {
            return
        }
        let ci = ciContext.createCGImage(ciImage, from: ciImage.extent)
        var buf  = calculateHistrogram(image:ci!)
        print(buf)
        self.currentCIImage = filteredCIImage
        
        mtkview.draw()
        
        let uiImage = UIImage(ciImage: filteredCIImage)
        
        if !takePicture {
            return
        }
        
        DispatchQueue.main.async {
            self.imagePreviewView.image = uiImage
            self.takePicture = false
        }
    }
        
}

extension ViewController : MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {

    }
    
    func draw(in view: MTKView) {
         guard let commandBuffer = metalCommandQueue.makeCommandBuffer() else {
            return
        }
        
         guard let ciImage = currentCIImage else {
            return
        }
        
         guard let currentDrawable = view.currentDrawable else {
            return
        }

       let heightOfciImage = ciImage.extent.height
        let heightOfDrawable = view.drawableSize.height
        let yOffsetFromBottom = (heightOfDrawable - heightOfciImage)/2
        
        self.ciContext.render(ciImage,
                              to: currentDrawable.texture,
                   commandBuffer: commandBuffer,
                          bounds: CGRect(origin: CGPoint(x: 0, y: -yOffsetFromBottom), size: view.drawableSize),
                      colorSpace: CGColorSpaceCreateDeviceRGB())
        
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
}


