//
//  ContentView.swift
//  motion_data_app
//
//  Created by Macintosh on 4/19/25.
//

import SwiftUI
import CoreMotion
import Charts

enum MeasureMode {
    case accelerometer
    case gyroscope
    case complementary
}

struct ContentView: View {
    @State private var motionManager = CMMotionManager()
    @State private var timer: Timer?
    @State private var updateTimer: Timer?
    
    @State private var timerPublisher: Publishers.Autoconnect<Timer.TimerPublisher>?
    @State private var timerCancellable: AnyCancellable?
    
    // calibration
    @State private var accelBias = SIMD3<Double>(x: 0, y: 0, z: 0)
    @State private var gyroBias = SIMD3<Double>(x: 0, y: 0, z: 0)
    @State private var accelNoise = SIMD3<Double>(x: 0, y: 0, z: 0)
    @State private var gyroNoise = SIMD3<Double>(x: 0, y: 0, z: 0)
    
    @State private var isCalibrating = false
    @State private var calibrationType = ""
    @State private var samplesCollected = 0
    @State private var totalSamples = 500
    
    @State private var accelSamples = [SIMD3<Double>]()
    @State private var gyroSamples = [SIMD3<Double>]()
    
    // plotting
    @State private var isTracking = false
    @State private var measureMode: MeasureMode = .accelerometer
    @State private var tiltAngleX: [Double] = []
    @State private var tiltAngleY: [Double] = []
    @State private var timestamps: [Double] = []
    @State private var startTime: Date?
    
    // sensor values
    @State private var accelAngleX: Double = 0
    @State private var accelAngleY: Double = 0
    
    @State private var gyroAngleX: Double = 0
    @State private var gyroAngleY: Double = 0
    
    @State private var compAngleX: Double = 0
    @State private var compAngleY: Double = 0
    
    @State private var currentTilt: Double = 0
    
    @State private var selectedAngleType = "X"
    
    let refreshRate = 0.02
    let alpha = 0.99
    
    var body: some View {
        VStack(spacing: 20) {
            GroupBox(label: Text("Sensor Calibration")
                .font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        if isCalibrating {
                            Text("Calibrating \(calibrationType): \(samplesCollected)/\(totalSamples) samples")
                        } else {
                            
                            Button("Calibrate Accelerometer") {
                                startCalibration(type: "accelerometer")
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            
                            Group {
                                Text("Accelerometer Bias: \(formatVector(accelBias))")
                                Text("Accelerometer Noise: \(formatVector(accelNoise))")
                            }
                            .font(.system(.body, design: .monospaced))
                            
                            Button("Calibrate Gyroscope") {
                                startCalibration(type: "gyroscope")
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            
                            Group {
                                Text("Gyroscope Bias: \(formatVector(gyroBias))")
                                Text("Gyroscope Noise: \(formatVector(gyroNoise))")
                            }
                            .font(.system(.body, design: .monospaced))
                        }
                    }
                    .padding()
                }
                .padding(.horizontal)
            
            GroupBox(label: Text("Motion Tracking")
                .font(.headline)) {
                    if measureMode == .complementary {Text("Tilt Magnitude: \(String(format: "%.2f°", currentTilt))").font(.headline).foregroundColor(.blue)
                 }
                    VStack(alignment: .leading, spacing: 10) {
                        if isTracking {
                            HStack {
                                Text("Mode: ")
                                switch measureMode {
                                case .accelerometer:
                                    Text("Accelerometer")
                                case .gyroscope:
                                    Text("Gyroscope")
                                case .complementary:
                                    Text("Complementary")
                                }
                                
                                Spacer()
                            }
                            
                            chartView
                                .frame(height: 250)
                                .padding(.vertical)
                            
                            HStack {
                                Picker("Angle", selection: $selectedAngleType) {
                                    Text("Pitch").tag("X")
                                    Text("Roll").tag("Y")
                                }
                                .pickerStyle(.segmented)
                                
                                Spacer()
                                
                                Button("Exit") {
                                    stopTracking()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        } else {
                            Picker("Tracking Mode", selection: $measureMode) {
                                Text("Accelerometer").tag(MeasureMode.accelerometer)
                                Text("Gyroscope").tag(MeasureMode.gyroscope)
                                Text("Complementary").tag(MeasureMode.complementary)
                            }
                            .pickerStyle(.segmented)
                            .padding(.vertical)
                            
                            Button("Start Tracking") {
                                startTracking()
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding()
                }
                .padding(.horizontal)
            
            Spacer()
        }
        .onDisappear {
            stopMotionUpdates()
        }
    }
    
    var chartView: some View {
        Chart {
            ForEach(0..<min(timestamps.count, selectedAngleType == "X" ? tiltAngleX.count : tiltAngleY.count), id: \.self) { i in
                LineMark(
                    x: .value("Time", timestamps[i]),
                    y: .value("Angle", selectedAngleType == "X" ? tiltAngleX[i] : tiltAngleY[i])
                )
            }
        }
        .chartYScale(domain: -90...90)
        .chartXScale(domain: 0...60)
        .chartYAxis {
            AxisMarks(values: [-90, -45, 0, 45, 90]) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel("\(value.as(Int.self) ?? 0)°")
            }
        }
        .chartXAxis {
            AxisMarks(values: [0, 15, 30, 45, 60]) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel("\(value.as(Int.self) ?? 0)s")
            }
        }
    }
    

    func formatVector(_ vector: SIMD3<Double>) -> String {
        return String(format: "[%.4f, %.4f, %.4f]", vector.x, vector.y, vector.z)
    }
    
    func startCalibration(type: String) {
        guard !isCalibrating else { return }
        
        isCalibrating = true
        calibrationType = type
        samplesCollected = 0
        
        if type == "accelerometer" {
            accelSamples.removeAll()
            startAccelerometerUpdates()
        } else {
            gyroSamples.removeAll()
            startGyroscopeUpdates()
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if samplesCollected >= totalSamples {
                finishCalibration()
            }
        }
    }
    
    func finishCalibration() {
        timer?.invalidate()
        timer = nil
        
        if calibrationType == "accelerometer" {
            calibrateAccel()
        } else {
            calibrateGyro()
        }
        
        stopMotionUpdates()
        isCalibrating = false
    }
    
    func calibrateAccel() {
        // bias
        var sumX = 0.0, sumY = 0.0, sumZ = 0.0
        
        for sample in accelSamples {
            sumX += sample.x
            sumY += sample.y
            sumZ += sample.z + 1.0
        }
        
        let count = Double(accelSamples.count)
        accelBias = SIMD3<Double>(
            x: sumX / count,
            y: sumY / count,
            z: sumZ / count
        )
        
        // noise
        var varianceX = 0.0, varianceY = 0.0, varianceZ = 0.0
        
        for sample in accelSamples {
            varianceX += pow(sample.x - accelBias.x, 2)
            varianceY += pow(sample.y - accelBias.y, 2)
            varianceZ += pow(sample.z + 1.0 - accelBias.z, 2)
        }
        
        accelNoise = SIMD3<Double>(
            x: sqrt(varianceX / count),
            y: sqrt(varianceY / count),
            z: sqrt(varianceZ / count)
        )
    }
    
    func calibrateGyro() {
        // bias
        var sumX = 0.0, sumY = 0.0, sumZ = 0.0
        
        for sample in gyroSamples {
            sumX += sample.x
            sumY += sample.y
            sumZ += sample.z
        }
        
        let count = Double(gyroSamples.count)
        gyroBias = SIMD3<Double>(
            x: sumX / count,
            y: sumY / count,
            z: sumZ / count
        )
        
        // noise
        var varianceX = 0.0, varianceY = 0.0, varianceZ = 0.0
        
        for sample in gyroSamples {
            varianceX += pow(sample.x - gyroBias.x, 2)
            varianceY += pow(sample.y - gyroBias.y, 2)
            varianceZ += pow(sample.z - gyroBias.z, 2)
        }
        
        gyroNoise = SIMD3<Double>(
            x: sqrt(varianceX / count),
            y: sqrt(varianceY / count),
            z: sqrt(varianceZ / count)
        )
    }
    
    
    func startTracking() {
        tiltAngleX.removeAll()
        tiltAngleY.removeAll()
        timestamps.removeAll()
        
        gyroAngleX = 0
        gyroAngleY = 0
        compAngleX = 0
        compAngleY = 0
        
        startTime = Date()
        isTracking = true
        
        motionManager.accelerometerUpdateInterval = refreshRate
        motionManager.gyroUpdateInterval = refreshRate
        
        motionManager.startAccelerometerUpdates()
        motionManager.startGyroUpdates()
        
        timerPublisher = Timer.publish(every: refreshRate, on: .main, in: .common).autoconnect()
        timerCancellable = timerPublisher?.sink { _ in
            self.processMotionData()
        }
        
        // stop after 60 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { _ in
            stopTracking()
        }
    }
    
    func processMotionData() {
        guard let startTime = startTime, isTracking else { return }
        
        if let accelData = motionManager.accelerometerData,
           let gyroData = motionManager.gyroData {
            
            let elapsedTime = -startTime.timeIntervalSinceNow
            
            // accelerometer data
            let ax = accelData.acceleration.x - accelBias.x
            let ay = accelData.acceleration.y - accelBias.y
            let az = accelData.acceleration.z - accelBias.z
            
            accelAngleX = atan2(ay, sqrt(ax*ax + az*az)) * 180.0 / .pi
            accelAngleY = atan2(-ax, sqrt(ay*ay + az*az)) * 180.0 / .pi
            
            // gyro data, flip!
            let gx = -(gyroData.rotationRate.x - gyroBias.x)
            let gy = -(gyroData.rotationRate.y - gyroBias.y)
            
            gyroAngleX += gx * refreshRate * 180.0 / .pi
            gyroAngleY += gy * refreshRate * 180.0 / .pi
            
            // complementary filter
            compAngleX = alpha * (compAngleX + gx * refreshRate * 180.0 / .pi) + (1.0 - alpha) * accelAngleX
            compAngleY = alpha * (compAngleY + gy * refreshRate * 180.0 / .pi) + (1.0 - alpha) * accelAngleY
            
            // tilt
            if measureMode == .complementary {
                currentTilt = sqrt(pow(compAngleX, 2) + pow(compAngleY, 2))
            }
            
            var angleX: Double
            var angleY: Double
            
            switch measureMode {
            case .accelerometer:
                angleX = accelAngleX
                angleY = accelAngleY
            case .gyroscope:
                angleX = gyroAngleX
                angleY = gyroAngleY
            case .complementary:
                angleX = compAngleX
                angleY = compAngleY
            }
            
            addDataPoint(x: angleX, y: angleY, time: elapsedTime)
        }
    }
    
    func stopTracking() {
        currentTilt = 0.0
        
        timerCancellable?.cancel()
        timerCancellable = nil
        timerPublisher = nil
        
        timer?.invalidate()
        timer = nil
        
        stopMotionUpdates()
        isTracking = false
    }
    
    func startAccelerometerUpdates(forCalibration: Bool = true) {
        motionManager.accelerometerUpdateInterval = refreshRate
        
        if forCalibration {
            motionManager.startAccelerometerUpdates(to: .main) { data, error in
                guard let data = data, error == nil else { return }
                self.handleAccelCalibration(data)
            }
        } else {
            motionManager.startAccelerometerUpdates()
        }
    }
    
    func startGyroscopeUpdates(forCalibration: Bool = true) {
        motionManager.gyroUpdateInterval = refreshRate
        
        if forCalibration {
            motionManager.startGyroUpdates(to: .main) { data, error in
                guard let data = data, error == nil else { return }
                self.handleGyroCalibration(data)
            }
        } else {
            motionManager.startGyroUpdates()
        }
    }
    
    func stopMotionUpdates() {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
    }
    
    func handleAccelCalibration(_ data: CMAccelerometerData) {
        let sample = SIMD3<Double>(x: data.acceleration.x, y: data.acceleration.y, z: data.acceleration.z)
        accelSamples.append(sample)
        samplesCollected = accelSamples.count
    }
    
    func handleGyroCalibration(_ data: CMGyroData) {
        let sample = SIMD3<Double>(x: data.rotationRate.x, y: data.rotationRate.y, z: data.rotationRate.z)
        gyroSamples.append(sample)
        samplesCollected = gyroSamples.count
    }
    
    func addDataPoint(x: Double, y: Double, time: TimeInterval) {
        tiltAngleX.append(x)
        tiltAngleY.append(y)
        timestamps.append(time)
    }
}

#Preview {
    ContentView()
}
