import AVKit
import VideoToolbox

protocol AfterPermissions {
    func permissionDidComplete(granted: Bool, showedPrompt: Bool)
}

class VideoFeed {
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }

    let session = AVCaptureSession()
    private var isSessionRunning = false
    private let sessionQueue = DispatchQueue(label: "session queue")
    private var setupResult: SessionSetupResult = .success
    var videoDeviceInput: AVCaptureDeviceInput!
    var videoDevice: AVCaptureDevice?
    var videoDeviceConnection: AVCaptureConnection?
    var torch: Torch?

    func pauseSession() {
        self.sessionQueue.suspend()
    }

    func requestCameraAccess(permissionDelegate: AfterPermissions?) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.sessionQueue.resume()
            DispatchQueue.main.async {
                permissionDelegate?.permissionDidComplete(granted: true, showedPrompt: false)
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(
                for: .video,
                completionHandler: { granted in
                    if !granted {
                        self.setupResult = .notAuthorized
                    }
                    self.sessionQueue.resume()
                    DispatchQueue.main.async {
                        permissionDelegate?.permissionDidComplete(
                            granted: granted,
                            showedPrompt: true
                        )
                    }
                }
            )

        default:
            // The user has previously denied access.
            self.setupResult = .notAuthorized
            DispatchQueue.main.async {
                permissionDelegate?.permissionDidComplete(granted: false, showedPrompt: false)
            }
        }
    }

    func setup(
        captureDelegate: AVCaptureVideoDataOutputSampleBufferDelegate,
        initialVideoOrientation: AVCaptureVideoOrientation,
        completion: @escaping ((_ success: Bool) -> Void)
    ) {
        sessionQueue.async {
            self.configureSession(
                captureDelegate: captureDelegate,
                initialVideoOrientation: initialVideoOrientation,
                completion: completion
            )
        }
    }

    func configureSession(
        captureDelegate: AVCaptureVideoDataOutputSampleBufferDelegate,
        initialVideoOrientation: AVCaptureVideoOrientation,
        completion: @escaping ((_ success: Bool) -> Void)
    ) {
        if setupResult != .success {
            DispatchQueue.main.async { completion(false) }
            return
        }

        session.beginConfiguration()

        do {
            var defaultVideoDevice: AVCaptureDevice? = getAvailableVideoDevice()   
            guard let myVideoDevice = defaultVideoDevice else {
                setupResult = .configurationFailed
                session.commitConfiguration()
                DispatchQueue.main.async { completion(false) }
                return
            }

            self.videoDevice = myVideoDevice
            self.torch = Torch(device: myVideoDevice)
            let videoDeviceInput = try AVCaptureDeviceInput(device: myVideoDevice)

            self.setupVideoDeviceDefaults()

            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
            } else {
                setupResult = .configurationFailed
                session.commitConfiguration()
                DispatchQueue.main.async { completion(false) }
                return
            }

            let videoDeviceOutput = AVCaptureVideoDataOutput()
            videoDeviceOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as AnyHashable as! String: Int(
                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                ),
            ]

            videoDeviceOutput.alwaysDiscardsLateVideoFrames = true
            let captureSessionQueue = DispatchQueue(label: "camera output queue")
            videoDeviceOutput.setSampleBufferDelegate(captureDelegate, queue: captureSessionQueue)
            guard session.canAddOutput(videoDeviceOutput) else {
                setupResult = .configurationFailed
                session.commitConfiguration()
                DispatchQueue.main.async { completion(false) }
                return
            }
            session.addOutput(videoDeviceOutput)

            if session.canSetSessionPreset(.high) {
                session.sessionPreset = .high
            }

            self.videoDeviceConnection = videoDeviceOutput.connection(with: .video)
            if self.videoDeviceConnection?.isVideoOrientationSupported ?? false {
                self.videoDeviceConnection?.videoOrientation = initialVideoOrientation
            }
        } catch {
            setupResult = .configurationFailed
            session.commitConfiguration()
            DispatchQueue.main.async { completion(false) }
            return
        }

        session.commitConfiguration()
        DispatchQueue.main.async { completion(true) }
    }

    func setupVideoDeviceDefaults() {
        guard let videoDevice = self.videoDevice else {
            return
        }

        guard (try? videoDevice.lockForConfiguration()) != nil else {
            return
        }

        if videoDevice.isFocusModeSupported(.continuousAutoFocus) {
            videoDevice.focusMode = .continuousAutoFocus
            if videoDevice.isSmoothAutoFocusSupported {
                videoDevice.isSmoothAutoFocusEnabled = true
            }
        }

        if videoDevice.isExposureModeSupported(.continuousAutoExposure) {
            videoDevice.exposureMode = .continuousAutoExposure
        }

        if videoDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            videoDevice.whiteBalanceMode = .continuousAutoWhiteBalance
        }

        if videoDevice.isLowLightBoostSupported {
            videoDevice.automaticallyEnablesLowLightBoostWhenAvailable = true
        }
        videoDevice.unlockForConfiguration()
    }

    // MARK: - Torch Logic
    func toggleTorch() {
        self.torch?.toggle()
    }

    func isTorchOn() -> Bool {
        return self.torch?.state == Torch.State.on
    }

    func hasTorchAndIsAvailable() -> Bool {
        let hasTorch = self.torch?.device?.hasTorch ?? false
        let isTorchAvailable = self.torch?.device?.isTorchAvailable ?? false
        return hasTorch && isTorchAvailable
    }

    func setTorchLevel(level: Float) {
        self.torch?.level = level
    }

`import AVFoundation

enum CameraError: Error {
    case noAvailableCamera
}

private func getAvailableVideoDevice() throws -> AVCaptureDevice {
    // Define a helper function to find a device from a list of device types
    func findDevice(for deviceTypes: [AVCaptureDevice.DeviceType], position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        return AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: position).devices.first
    }

    // Attempt to find the best available back camera
    if let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
        return device
    } else if let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
        return device
    } else if let device = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
        return device
    } else if let device = findDevice(for: [.builtInWideAngleCamera, .builtInTelephotoCamera], position: .back) {
        return device
    } else if let device = findDevice(for: [
        .builtInDualCamera,
        .builtInTripleCamera,
        .builtInTelephotoCamera,
        .builtInDualWideCamera,
        .builtInTrueDepthCamera,
        .builtInWideAngleCamera,
        .builtInUltraWideCamera
    ], position: .back) {
        return device
    }

    // Fallback to front camera if no back camera is available
    if let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
        return frontCamera
    }

    // Throw an error if no cameras are available
    throw CameraError.noAvailableCamera
}


    // MARK: - VC Lifecycle Logic
    func willAppear() {
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
            case _:
                break
            }
        }
    }

    func willDisappear() {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
            }
        }
    }
}
