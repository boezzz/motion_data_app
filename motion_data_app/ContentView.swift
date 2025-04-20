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
    
    // complementary filter
    @State private var cAngleX: Double = 0
    @State private var cAngleY: Double = 0
    @State private var lastGyroUpdateTime: Date?
    
    
    @State private var selectedAngleType = "X"
    
    @State private var lastAccelAngleX: Double = 0
    @State private var lastAccelAngleY: Double = 0
    
    // low pass filter
    @State private var filteredAccelAngleX: Double = 0
    @State private var filteredAccelAngleY: Double = 0
    
    let smoothingAlpha = 0.2
    
    let refreshRate = 0.05
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
                        Text("Select a mode")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
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
        guard !isTracking else { return }
        
        tiltAngleX.removeAll()
        tiltAngleY.removeAll()
        timestamps.removeAll()
        cAngleX = 0
        cAngleY = 0
        
        startTime = Date()
        lastGyroUpdateTime = startTime
        isTracking = true
        
        switch measureMode {
        case .accelerometer:
            startAccelerometerUpdates(forCalibration: false)
        case .gyroscope:
            startGyroscopeUpdates(forCalibration: false)
        case .complementary:
            startAccelerometerUpdates(forCalibration: false)
            startGyroscopeUpdates(forCalibration: false)
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { _ in
            stopTracking()
        }
        
    }
    
    func stopTracking() {
        timer?.invalidate()
        timer = nil
        stopMotionUpdates()
        isTracking = false
    }
    
    
    func startAccelerometerUpdates(forCalibration: Bool = true) {
        motionManager.accelerometerUpdateInterval = refreshRate
        motionManager.startAccelerometerUpdates(to: .main) { data, error in
            guard let data = data, error == nil else { return }
            
            if forCalibration {
                handleAccelerometerCalibrationData(data)
            } else if isTracking {
                handleAccelerometerTrackingData(data)
            }
        }
    }
    
    func startGyroscopeUpdates(forCalibration: Bool = true) {
        motionManager.gyroUpdateInterval = refreshRate
        motionManager.startGyroUpdates(to: .main) { data, error in
            guard let data = data, error == nil else { return }
            
            if forCalibration {
                handleGyroscopeCalibrationData(data)
            } else if isTracking {
                handleGyroscopeTrackingData(data)
            }
        }
    }
    
    func stopMotionUpdates() {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
    }
    
    
    func handleAccelerometerCalibrationData(_ data: CMAccelerometerData) {
        let sample = SIMD3<Double>(x: data.acceleration.x, y: data.acceleration.y, z: data.acceleration.z)
        accelSamples.append(sample)
        samplesCollected = accelSamples.count
    }
    
    func handleGyroscopeCalibrationData(_ data: CMGyroData) {
        let sample = SIMD3<Double>(x: data.rotationRate.x, y: data.rotationRate.y, z: data.rotationRate.z)
        gyroSamples.append(sample)
        samplesCollected = gyroSamples.count
    }
    
    func handleAccelerometerTrackingData(_ data: CMAccelerometerData) {
        guard let startTime = startTime, isTracking else { return }

        let x = data.acceleration.x - accelBias.x
        let y = data.acceleration.y - accelBias.y
        let z = data.acceleration.z - accelBias.z

        let accelAngleX = atan2(y, sqrt(x*x + z*z)) * 180.0 / .pi
        let accelAngleY = atan2(-x, sqrt(y*y + z*z)) * 180.0 / .pi

        lastAccelAngleX = accelAngleX
        lastAccelAngleY = accelAngleY

        if measureMode == .accelerometer {
            addDataPoint(x: accelAngleX, y: accelAngleY, time: -startTime.timeIntervalSinceNow)
        }
    }


    func handleGyroscopeTrackingData(_ data: CMGyroData) {
        guard let startTime = startTime, isTracking else { return }

        let x = data.rotationRate.x - gyroBias.x
        let y = data.rotationRate.y - gyroBias.y

        let currentTime = Date()

        guard let lastUpdateTime = lastGyroUpdateTime else {
            lastGyroUpdateTime = currentTime
            return
        }

        let dt = currentTime.timeIntervalSince(lastUpdateTime)
        lastGyroUpdateTime = currentTime

        if measureMode == .gyroscope {
            if tiltAngleX.isEmpty {
                tiltAngleX.append(0)
                tiltAngleY.append(0)
                timestamps.append(0)
            } else {
                let lastX = tiltAngleX.last!
                let lastY = tiltAngleY.last!

                let newX = lastX + x * dt * 180.0 / .pi
                let newY = lastY + y * dt * 180.0 / .pi

                addDataPoint(x: newX, y: newY, time: -startTime.timeIntervalSinceNow)
            }
        } else if measureMode == .complementary {
            if tiltAngleX.isEmpty {
                tiltAngleX.append(0)
                tiltAngleY.append(0)
                timestamps.append(0)
            }

            // integrate gyro angle
            let gyroAngleDeltaX = x * dt * 180.0 / .pi
            let gyroAngleDeltaY = y * dt * 180.0 / .pi

            if let accelData = motionManager.accelerometerData {
                let ax = accelData.acceleration.x - accelBias.x
                let ay = accelData.acceleration.y - accelBias.y
                let az = accelData.acceleration.z - accelBias.z

                let rawAccelAngleX = atan2(ay, sqrt(ax*ax + az*az)) * 180.0 / .pi
                let rawAccelAngleY = atan2(-ax, sqrt(ay*ay + az*az)) * 180.0 / .pi

                // apply low-pass filter to accelerometer angles
                filteredAccelAngleX = smoothingAlpha * rawAccelAngleX + (1 - smoothingAlpha) * filteredAccelAngleX
                filteredAccelAngleY = smoothingAlpha * rawAccelAngleY + (1 - smoothingAlpha) * filteredAccelAngleY

                // complementary filter
                cAngleX = alpha * (tiltAngleX.last! + gyroAngleDeltaX) + (1 - alpha) * filteredAccelAngleX
                cAngleY = alpha * (tiltAngleY.last! + gyroAngleDeltaY) + (1 - alpha) * filteredAccelAngleY
            }

            addDataPoint(x: cAngleX, y: cAngleY, time: -startTime.timeIntervalSinceNow)
        }

    }

    
    func addDataPoint(x: Double, y: Double, time: TimeInterval) {
        guard timestamps.isEmpty || time - (timestamps.last ?? 0) >= refreshRate * 0.9 else { return }
                
        tiltAngleX.append(x)
        tiltAngleY.append(y)
        timestamps.append(time)
    }
}

#Preview {
    ContentView()
}
