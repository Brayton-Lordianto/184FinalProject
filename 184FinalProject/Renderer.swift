//
//  Renderer.swift
//  184FinalProject
//
//  Created by Brayton Lordianto on 4/14/25.
//

import CompositorServices
import Metal
import MetalKit
import simd
import Spatial

struct Vertex {
    var position: simd_float3
    var texCoord: simd_float2
    var normal: simd_float3
}


// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<UniformsArray>.size + 0xFF) & -0x100

let maxBuffersInFlight = 3

enum RendererError: Error {
    case badVertexDescriptor
}

extension LayerRenderer.Clock.Instant.Duration {
    var timeInterval: TimeInterval {
        let nanoseconds = TimeInterval(components.attoseconds / 1_000_000_000)
        return TimeInterval(components.seconds) + (nanoseconds / TimeInterval(NSEC_PER_SEC))
    }
}

final class RendererTaskExecutor: TaskExecutor {
    private let queue = DispatchQueue(label: "RenderThreadQueue", qos: .userInteractive)
    
    func enqueue(_ job: UnownedJob) {
        queue.async {
            job.runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }
    
    func asUnownedSerialExecutor() -> UnownedTaskExecutor {
        return UnownedTaskExecutor(ordinary: self)
    }
    
    static var shared: RendererTaskExecutor = RendererTaskExecutor()
}

actor Renderer {
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var dynamicUniformBuffer: MTLBuffer
    var pipelineState: MTLRenderPipelineState
    var depthState: MTLDepthStencilState
    var colorMap: MTLTexture
    
    // MARK: let's try to make compute pipeline for compute shaders
    var computePipelines: [String: MTLComputePipelineState] = [:]
    var computeOutputTexture: MTLTexture?
    var computeTime: Float = 0.0
    
    // MARK: Model triangle data for path tracing
    var triangleBuffer: MTLBuffer?
    var triangleCount: Int = 0
    
    
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    
    var uniformBufferOffset = 0
    
    var uniformBufferIndex = 0
    
    var uniforms: UnsafeMutablePointer<UniformsArray>
    
    let rasterSampleCount: Int
    var memorylessTargetIndex: Int = 0
    var memorylessTargets: [(color: MTLTexture, depth: MTLTexture)?]
    
    var rotation: Float = 0
    
    var mesh: MTKMesh
    
    let arSession: ARKitSession
    let worldTracking: WorldTrackingProvider
    let layerRenderer: LayerRenderer
    let appModel: AppModel
    
    var lastCameraPosition: SIMD3<Float>?
    
    /*
     type Sphere
     let spheres: [Sphere]
     */
    
    init(_ layerRenderer: LayerRenderer, appModel: AppModel) {
        self.device = layerRenderer.device
        self.layerRenderer = layerRenderer
        self.commandQueue = self.device.makeCommandQueue()!
        self.appModel = appModel

        
        let device = self.device
        if device.supports32BitMSAA && device.supportsTextureSampleCount(4) {
            rasterSampleCount = 4
        } else {
            rasterSampleCount = 1
        }
        
        let uniformBufferSize = alignedUniformsSize * maxBuffersInFlight
        
        self.dynamicUniformBuffer = self.device.makeBuffer(length:uniformBufferSize,
                                                           options:[MTLResourceOptions.storageModeShared])!
        
        self.dynamicUniformBuffer.label = "UniformBuffer"
        
        self.memorylessTargets = .init(repeating: nil, count: maxBuffersInFlight)
        
        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents()).bindMemory(to:UniformsArray.self, capacity:1)
        
        let mtlVertexDescriptor = Renderer.buildMetalVertexDescriptor()
        
        do {
            pipelineState = try Renderer.buildRenderPipelineWithDevice(device: device,
                                                                       layerRenderer: layerRenderer,
                                                                       rasterSampleCount: rasterSampleCount,
                                                                       mtlVertexDescriptor: mtlVertexDescriptor)
        } catch {
            fatalError("Unable to compile render pipeline state.  Error info: \(error)")
        }
        
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = MTLCompareFunction.greater
        depthStateDescriptor.isDepthWriteEnabled = true
        self.depthState = device.makeDepthStencilState(descriptor:depthStateDescriptor)!
        
        do {
            mesh = try Renderer.buildMesh(device: device, mtlVertexDescriptor: mtlVertexDescriptor)
        } catch {
            fatalError("Unable to build MetalKit Mesh. Error info: \(error)")
        }
        
        do {
            colorMap = try Renderer.loadTexture(device: device, textureName: "ColorMap")
        } catch {
            fatalError("Unable to load texture. Error info: \(error)")
        }
        
        worldTracking = WorldTrackingProvider()
        arSession = ARKitSession()
        
        
        
        
        // MARK: Set up vertex descriptor for models
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.layouts[30].stride = MemoryLayout<Vertex>.stride
        vertexDescriptor.layouts[30].stepRate = 1
        vertexDescriptor.layouts[30].stepFunction = MTLVertexStepFunction.perVertex

        vertexDescriptor.attributes[0].format = MTLVertexFormat.float3
        vertexDescriptor.attributes[0].offset = MemoryLayout.offset(of: \Vertex.position)!
        vertexDescriptor.attributes[0].bufferIndex = 30

        vertexDescriptor.attributes[1].format = MTLVertexFormat.float2
        vertexDescriptor.attributes[1].offset = MemoryLayout.offset(of: \Vertex.texCoord)!
        vertexDescriptor.attributes[1].bufferIndex = 30
        
        vertexDescriptor.attributes[2].format = MTLVertexFormat.float3
        vertexDescriptor.attributes[2].offset = MemoryLayout.offset(of: \Vertex.normal)!
        vertexDescriptor.attributes[2].bufferIndex = 30
        
        // Load the appropriate model based on appModel.selectedModel
        let textureLoader = MTKTextureLoader(device: layerRenderer.device)
        
        // Create triangles based on the selected model type
        Task { @MainActor in
            var gpuTriangles: [GPUTriangle]
            let obj: Model?
            
            if self.appModel.selectedModel.useFakeTriangles {
                // Use fake triangles (custom Cornell box)
                gpuTriangles = fakeTriangles.map { GPUTriangle(from: $0) }
                DispatchQueue.global().async {
                    self.triangleCount = gpuTriangles.count
                }
            } else {
                // Load a USDZ model
                let modelFilename = self.appModel.selectedModel.filename
                guard let url = Bundle.main.url(forResource: modelFilename, withExtension: "usdz") else {
                    fatalError("Failed to load model file: \(modelFilename).usdz")
                }
                
                obj = Model()
                obj!.loadModel(device: device, url: url, vertexDescriptor: vertexDescriptor, textureLoader: textureLoader)
                
                // Convert model to shader-compatible triangles
                let triangles = convertModelToShaderScene(model: obj!)
                
                // Create GPU triangles for passing to shader
                gpuTriangles = triangles.map { GPUTriangle(from: $0) }
                DispatchQueue.global().async {
                    self.triangleCount = gpuTriangles.count
                }
            }
            
            if !gpuTriangles.isEmpty {
                let triangleBufferSize = (MemoryLayout<GPUTriangle>.stride) * gpuTriangles.count
                let alignedTriangleBufferSize = (triangleBufferSize + 0xFF) & -0x100
                DispatchQueue.global().async {
                    self.triangleBuffer = device.makeBuffer(bytes: &gpuTriangles,
                                                            length: alignedTriangleBufferSize,
                                                            options: .storageModeShared)
                    self.triangleBuffer?.label = "Model Triangles Buffer"
                }
            }
        }
        // MARK: END
    }
    
    private func startARSession() async {
        do {
            try await arSession.run([worldTracking])
        } catch {
            fatalError("Failed to initialize ARSession")
        }
    }
    
    @MainActor
    static func startRenderLoop(_ layerRenderer: LayerRenderer, appModel: AppModel) {
        Task(executorPreference: RendererTaskExecutor.shared) {
            let renderer = Renderer(layerRenderer, appModel: appModel)
            await renderer.startARSession()
            await renderer.renderLoop()
        }
    }
    
    static func buildMetalVertexDescriptor() -> MTLVertexDescriptor {
        // Create a Metal vertex descriptor specifying how vertices will by laid out for input into our render
        //   pipeline and how we'll layout our Model IO vertices
        
        let mtlVertexDescriptor = MTLVertexDescriptor()
        
        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].format = MTLVertexFormat.float3
        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].offset = 0
        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].bufferIndex = BufferIndex.meshPositions.rawValue
        
        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].format = MTLVertexFormat.float2
        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].offset = 0
        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].bufferIndex = BufferIndex.meshGenerics.rawValue
        
        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stride = 12
        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepRate = 1
        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepFunction = MTLVertexStepFunction.perVertex
        
        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stride = 8
        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepRate = 1
        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepFunction = MTLVertexStepFunction.perVertex
        
        return mtlVertexDescriptor
    }
    
    static func buildRenderPipelineWithDevice(device: MTLDevice,
                                              layerRenderer: LayerRenderer,
                                              rasterSampleCount: Int,
                                              mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTLRenderPipelineState {
        /// Build a render state pipeline object
        
        let library = device.makeDefaultLibrary()
        
        let vertexFunction = library?.makeFunction(name: "vertexShader")
        let fragmentFunction = library?.makeFunction(name: "fragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "RenderPipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor
        pipelineDescriptor.rasterSampleCount = rasterSampleCount
        
        pipelineDescriptor.colorAttachments[0].pixelFormat = layerRenderer.configuration.colorFormat
        pipelineDescriptor.depthAttachmentPixelFormat = layerRenderer.configuration.depthFormat
        
        pipelineDescriptor.maxVertexAmplificationCount = layerRenderer.properties.viewCount
        
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    static func buildMesh(device: MTLDevice,
                          mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTKMesh {
        /// Create and condition mesh data to feed into a pipeline using the given vertex descriptor
        
        let metalAllocator = MTKMeshBufferAllocator(device: device)
        
        var mdlMesh = MDLMesh.newBox(withDimensions: SIMD3<Float>(4, 4, 4),
                                     segments: SIMD3<UInt32>(2, 2, 2),
                                     geometryType: MDLGeometryType.triangles,
                                     inwardNormals:false,
                                     allocator: metalAllocator)
        
        // MARK: make it a sphere
        let r = 20.0
        mdlMesh =  MDLMesh.newEllipsoid(
            withRadii: SIMD3<Float>(Float(r), Float(r), Float(r)),
            radialSegments: 400,
            verticalSegments: 400,
            geometryType: .triangles,
            inwardNormals: false,
            hemisphere: false,
            allocator: metalAllocator
        )
        // MARK: ===============

        
        let mdlVertexDescriptor = MTKModelIOVertexDescriptorFromMetal(mtlVertexDescriptor)
        
        guard let attributes = mdlVertexDescriptor.attributes as? [MDLVertexAttribute] else {
            throw RendererError.badVertexDescriptor
        }
        attributes[VertexAttribute.position.rawValue].name = MDLVertexAttributePosition
        attributes[VertexAttribute.texcoord.rawValue].name = MDLVertexAttributeTextureCoordinate
        
        mdlMesh.vertexDescriptor = mdlVertexDescriptor
        
        return try MTKMesh(mesh:mdlMesh, device:device)
    }
    
    static func loadTexture(device: MTLDevice,
                            textureName: String) throws -> MTLTexture {
        /// Load texture data with optimal parameters for sampling
        
        let textureLoader = MTKTextureLoader(device: device)
        
        let textureLoaderOptions = [
            MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.`private`.rawValue)
        ]
        
        return try textureLoader.newTexture(name: textureName,
                                            scaleFactor: 1.0,
                                            bundle: nil,
                                            options: textureLoaderOptions)
    }
    
    // MARK: compute pipeline
    private var accumulationTexture: MTLTexture?
    private var pathTracerOutputTexture: MTLTexture?
    private var denoisedTexture: MTLTexture?    // New texture for denoised output
    private var sampleCount: UInt32 = 0
    private var camMovement: Float = 0
    private var lastFrameTime: Double = 0
    private var isMoving: Bool = false
    
    // Flag to use enhanced denoiser (more quality but slightly more expensive)
    private var useEnhancedDenoiser: Bool = true
    
    private func setupComputePipelines() {
        guard let library = device.makeDefaultLibrary() else { return }
        
        // Create compute pipelines for your shaders
        if let function = library.makeFunction(name: "pathTracerCompute") {
            do {
                let pipeline = try device.makeComputePipelineState(function: function)
                computePipelines["pathTracerCompute"] = pipeline
            } catch {
                print("Failed to create compute pipeline for pathTracerCompute: \(error)")
            }
        }
        
        // Create accumulation shader pipeline
        if let function = library.makeFunction(name: "accumulationKernel") {
            do {
                let pipeline = try device.makeComputePipelineState(function: function)
                computePipelines["accumulationKernel"] = pipeline
            } catch {
                print("Failed to create compute pipeline for accumulationKernel: \(error)")
            }
        }
        
        // Create basic real-time denoising pipeline
        if let function = library.makeFunction(name: "fastDenoiseKernel") {
            do {
                let pipeline = try device.makeComputePipelineState(function: function)
                computePipelines["fastDenoiseKernel"] = pipeline
            } catch {
                print("Failed to create compute pipeline for fastDenoiseKernel: \(error)")
            }
        }
        
        // Create enhanced real-time denoising pipeline
        if let function = library.makeFunction(name: "enhancedDenoiseKernel") {
            do {
                let pipeline = try device.makeComputePipelineState(function: function)
                computePipelines["enhancedDenoiseKernel"] = pipeline
            } catch {
                print("Failed to create compute pipeline for enhancedDenoiseKernel: \(error)")
            }
        }
    }
    
    private func createComputeOutputTexture(width: Int, height: Int) {
        // Create textures with the same descriptor setup
        let createTexture = { () -> MTLTexture? in
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba32Float,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite]
            return self.device.makeTexture(descriptor: descriptor)
        }
        
        // Create textures for each stage of the pipeline
        pathTracerOutputTexture = createTexture()    // Raw output from pathTracer
        accumulationTexture = createTexture()        // Accumulated results
        denoisedTexture = createTexture()            // Denoised output
        computeOutputTexture = createTexture()       // Final output texture shown to the user
        
        // Reset sample count when creating new textures
        resetAccumulation()
    }
    
    private func resetAccumulation() {
        sampleCount = 0
        print("Resetting accumulation buffer")
        
        // Simply create a new texture when resetting instead of clearing the old one
        // This is more efficient in Metal and avoids synchronization issues
        guard let accumTexture = accumulationTexture else { return }
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: accumTexture.pixelFormat,
            width: accumTexture.width,
            height: accumTexture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        // Create a new texture with the same dimensions
        accumulationTexture = device.makeTexture(descriptor: descriptor)
    }
    // MARK: ===============
    
    private func updateDynamicBufferState() {
        /// Update the state of our uniform buffers before rendering
        
        uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight
        
        uniformBufferOffset = alignedUniformsSize * uniformBufferIndex
        
        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents() + uniformBufferOffset).bindMemory(to:UniformsArray.self, capacity:1)
    }
    
    private func memorylessRenderTargets(drawable: LayerRenderer.Drawable) -> (color: MTLTexture, depth: MTLTexture) {
        
        func renderTarget(resolveTexture: MTLTexture, cachedTexture: MTLTexture?) -> MTLTexture {
            if let cachedTexture,
               resolveTexture.width == cachedTexture.width && resolveTexture.height == cachedTexture.height {
                return cachedTexture
            } else {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: resolveTexture.pixelFormat,
                                                                          width: resolveTexture.width,
                                                                          height: resolveTexture.height,
                                                                          mipmapped: false)
                descriptor.usage = .renderTarget
                descriptor.textureType = .type2DMultisampleArray
                descriptor.sampleCount = rasterSampleCount
                descriptor.storageMode = .memoryless
                descriptor.arrayLength = resolveTexture.arrayLength
                return resolveTexture.device.makeTexture(descriptor: descriptor)!
            }
        }
        
        memorylessTargetIndex = (memorylessTargetIndex + 1) % maxBuffersInFlight
        
        let cachedTargets = memorylessTargets[memorylessTargetIndex]
        let newTargets = (renderTarget(resolveTexture: drawable.colorTextures[0], cachedTexture: cachedTargets?.color),
                          renderTarget(resolveTexture: drawable.depthTextures[0], cachedTexture: cachedTargets?.depth))
        
        memorylessTargets[memorylessTargetIndex] = newTargets
        
        return newTargets
    }
    
    private func updateGameState(drawable: LayerRenderer.Drawable, deviceAnchor: DeviceAnchor?) {
        /// Update any game state before rendering
        
        let rotationAxis = SIMD3<Float>(1, 1, 0)
        let modelRotationMatrix = matrix4x4_rotation(radians: rotation, axis: rotationAxis)
//        let modelTranslationMatrix = matrix4x4_translation(0.0, 0.0, -8.0)
        let modelTranslationMatrix = matrix4x4_translation(0, 0, 0)
        let modelScaleMatrix = matrix4x4_scale(-1, 1, 1)
        //        let modelMatrix = modelTranslationMatrix * modelRotationMatrix
        let modelMatrix = modelTranslationMatrix * modelScaleMatrix
        
        let simdDeviceAnchor = deviceAnchor?.originFromAnchorTransform ?? matrix_identity_float4x4
        
        func uniforms(forViewIndex viewIndex: Int) -> Uniforms {
            let view = drawable.views[viewIndex]
            let viewMatrix = (simdDeviceAnchor * view.transform).inverse
            let projection = drawable.computeProjection(viewIndex: viewIndex)
            
            return Uniforms(projectionMatrix: projection, modelViewMatrix: viewMatrix * modelMatrix)
        }
        
        self.uniforms[0].uniforms.0 = uniforms(forViewIndex: 0)
        if drawable.views.count > 1 {
            self.uniforms[0].uniforms.1 = uniforms(forViewIndex: 1)
        }
        
        rotation += 0.01
    }
    
    func renderFrame() {
        /// Per frame updates hare
        
        guard let frame = layerRenderer.queryNextFrame() else { return }
        frame.startUpdate()
        // Perform frame independent work
        frame.endUpdate()
        guard let timing = frame.predictTiming() else { return }
        LayerRenderer.Clock().wait(until: timing.optimalInputTime)
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            fatalError("Failed to create command buffer")
        }
        guard let drawable = frame.queryDrawable() else { return }
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        frame.startSubmission()
        let time = LayerRenderer.Clock.Instant.epoch.duration(to: drawable.frameTiming.presentationTime).timeInterval
        let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: time)
        drawable.deviceAnchor = deviceAnchor
        let semaphore = inFlightSemaphore
        commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
            semaphore.signal()
        }
        self.updateDynamicBufferState()
        self.updateGameState(drawable: drawable, deviceAnchor: deviceAnchor)
        let renderPassDescriptor = MTLRenderPassDescriptor()
        if rasterSampleCount > 1 {
            let renderTargets = memorylessRenderTargets(drawable: drawable)
            renderPassDescriptor.colorAttachments[0].resolveTexture = drawable.colorTextures[0]
            renderPassDescriptor.colorAttachments[0].texture = renderTargets.color
            renderPassDescriptor.depthAttachment.resolveTexture = drawable.depthTextures[0]
            renderPassDescriptor.depthAttachment.texture = renderTargets.depth
            renderPassDescriptor.colorAttachments[0].storeAction = .multisampleResolve
            renderPassDescriptor.depthAttachment.storeAction = .multisampleResolve
        } else {
            renderPassDescriptor.colorAttachments[0].texture = drawable.colorTextures[0]
            renderPassDescriptor.depthAttachment.texture = drawable.depthTextures[0]
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            renderPassDescriptor.depthAttachment.storeAction = .store
        }
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.clearDepth = 0.0
        renderPassDescriptor.rasterizationRateMap = drawable.rasterizationRateMaps.first
        if layerRenderer.configuration.layout == .layered {
            renderPassDescriptor.renderTargetArrayLength = drawable.views.count
        }
        
        // Run compute pass before render pass
        dispatchComputeCommands(commandBuffer: commandBuffer, drawable: drawable, deviceAnchor: deviceAnchor)
        
        /// Final pass rendering code here
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            fatalError("Failed to create render encoder")
        }
        renderEncoder.label = "Primary Render Encoder"
        renderEncoder.pushDebugGroup("Draw Box")
        renderEncoder.setCullMode(.back)
        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setVertexBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
        let viewports = drawable.views.map { $0.textureMap.viewport }
        renderEncoder.setViewports(viewports)
        if drawable.views.count > 1 {
            var viewMappings = (0..<drawable.views.count).map {
                MTLVertexAmplificationViewMapping(viewportArrayIndexOffset: UInt32($0),
                                                  renderTargetArrayIndexOffset: UInt32($0))
            }
            renderEncoder.setVertexAmplificationCount(viewports.count, viewMappings: &viewMappings)
        }
        
        for (index, element) in mesh.vertexDescriptor.layouts.enumerated() {
            guard let layout = element as? MDLVertexBufferLayout else {
                return
            }
            
            if layout.stride != 0 {
                let buffer = mesh.vertexBuffers[index]
                renderEncoder.setVertexBuffer(buffer.buffer, offset:buffer.offset, index: index)
            }
        }
        
        renderEncoder.setFragmentTexture(colorMap, index: TextureIndex.color.rawValue)
        // MARK: set the compute texture
        renderEncoder.setFragmentTexture(computeOutputTexture, index: TextureIndex.compute.rawValue)
        // MARK: ===================
        for submesh in mesh.submeshes {
            renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                indexCount: submesh.indexCount,
                                                indexType: submesh.indexType,
                                                indexBuffer: submesh.indexBuffer.buffer,
                                                indexBufferOffset: submesh.indexBuffer.offset)
        }
        
        // MARK: Compute Pass
        func dispatchComputeCommands(commandBuffer: MTLCommandBuffer, drawable: LayerRenderer.Drawable, deviceAnchor: DeviceAnchor?) {
            guard let pathTracerPipeline = computePipelines["pathTracerCompute"],
                  let accumulationPipeline = computePipelines["accumulationKernel"],
                  let denoisePipeline = computePipelines["fastDenoiseKernel"],
                  let outputTexture = computeOutputTexture,
                  let pathTracerOutput = pathTracerOutputTexture,
                  let accumTexture = accumulationTexture,
                  let denoiseTexture = denoisedTexture else {
                return
            }
            
            // Increment time
            computeTime += Float(1.0/60.0)
            
            // Get the camera position to check for movement
            let simdDeviceAnchor = deviceAnchor?.originFromAnchorTransform ?? matrix_identity_float4x4
            let view = drawable.views[0]
            let viewMatrix = (simdDeviceAnchor * view.transform).inverse
            let currentCameraPosition = viewMatrix.columns.3.xyz
            
            // Check if camera moved - reset accumulation if significant movement occurred
            let currentTime = NSDate().timeIntervalSince1970
            let timeDelta = currentTime - lastFrameTime
            lastFrameTime = currentTime
            
            // Reset accumulation in certain conditions:
            // 1. If too much time passed between frames (likely due to head movement)
            // 2. If camera position changed significantly
            // 3. Every 500 samples to prevent numerical issues
            let cameraPosDiffThreshold: Float = 0.01
            let sampleCountThreshold: Int = 500
            if timeDelta > 0.5 || sampleCount > sampleCountThreshold ||
               (lastCameraPosition != nil && length(currentCameraPosition - lastCameraPosition!) > cameraPosDiffThreshold) {
                resetAccumulation()
            }
            
            // Update last camera position
            sampleCount += 1
            camMovement = length(currentCameraPosition - (lastCameraPosition ?? SIMD3<Float>(0, 0, 0)))
            lastCameraPosition = currentCameraPosition
            let cameraPosition = viewMatrix.columns.3.xyz
            let projection = drawable.computeProjection(viewIndex: 0)
            let fovY = 2.0 * atan(1.0 / projection.columns.1.y)
            var params = ComputeParams(
                time: computeTime,
                resolution: SIMD2<Float>(Float(outputTexture.width), Float(outputTexture.height)),
                frameIndex: UInt32(computeTime * 60) % 10000,
                sampleCount: sampleCount,
                cameraPosition: cameraPosition,
                viewMatrix: viewMatrix,
                fovY: fovY,
                modelTriangleCount: UInt32(triangleCount) // Pass the actual triangle count
            )
            
            // Calculate threads and threadgroups
            // pretty standard setup for compute shaders
            let threadsPerThreadgroup = MTLSize(width: 32, height: 8, depth: 1)
            let threadgroupCount = MTLSize(
                width: (outputTexture.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
                height: (outputTexture.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
                depth: 1
            )
            
            // PASS 1: Path Tracer - generates a single sample
            guard let pathTracerEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
            pathTracerEncoder.setComputePipelineState(pathTracerPipeline)
            pathTracerEncoder.setBytes(&params, length: MemoryLayout<ComputeParams>.size, index: 0)
            
            // Set the triangle buffer if available
            if let triangleBuffer = triangleBuffer {
                pathTracerEncoder.setBuffer(triangleBuffer, offset: 0, index: 1)
            }
            
            pathTracerEncoder.setTexture(pathTracerOutput, index: 0)
            pathTracerEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadsPerThreadgroup)
            pathTracerEncoder.endEncoding()
            
            // PASS 2: Accumulation Pass - combines this sample with previous samples
            guard let accumEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
            accumEncoder.setComputePipelineState(accumulationPipeline)
            accumEncoder.setBytes(&sampleCount, length: MemoryLayout<UInt32>.size, index: 0)
            accumEncoder.setTexture(pathTracerOutput, index: 0)
            accumEncoder.setTexture(accumTexture, index: 1)
            accumEncoder.setTexture(denoiseTexture, index: 2) // Now write to denoise texture instead of final output
            accumEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadsPerThreadgroup)
            accumEncoder.endEncoding()
            
            // PASS 3: Denoising Pass - apply real-time denoising to the accumulated result
            guard let denoiseEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
            
            // Select which denoiser to use based on the flag
            if useEnhancedDenoiser, let enhancedPipeline = computePipelines["enhancedDenoiseKernel"] {
                denoiseEncoder.setComputePipelineState(enhancedPipeline)
            } else {
                denoiseEncoder.setComputePipelineState(denoisePipeline)
            }
            
            denoiseEncoder.setBytes(&sampleCount, length: MemoryLayout<UInt32>.size, index: 0)
            denoiseEncoder.setTexture(denoiseTexture, index: 0) // Input is the accumulated result
            denoiseEncoder.setTexture(outputTexture, index: 1)  // Output is the final displayed texture
            denoiseEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadsPerThreadgroup)
            denoiseEncoder.endEncoding()
            
            // Copy accumulated result for next frame
            guard let copyEncoder = commandBuffer.makeBlitCommandEncoder() else { return }
            copyEncoder.copy(from: denoiseTexture, to: accumTexture)
            copyEncoder.endEncoding()
            
            print("Rendering sample \(sampleCount) with \(triangleCount) model triangles")
        }
        
        renderEncoder.popDebugGroup()
        renderEncoder.endEncoding()
        
        drawable.encodePresent(commandBuffer: commandBuffer)
        commandBuffer.commit()
        frame.endSubmission()
    }
    
    // Method to set up and initialize compute components
    private func setupComputeComponents() {
        setupComputePipelines()
        let resolution = 1440
        createComputeOutputTexture(width: resolution, height: resolution)
    }
    
    func renderLoop() {
        // Set up compute components at the start of the render loop
        setupComputeComponents()
        
        while true {
            if layerRenderer.state == .invalidated {
                print("Layer is invalidated")
                Task { @MainActor in
                    appModel.immersiveSpaceState = .closed
                }
                return
            } else if layerRenderer.state == .paused {
                Task { @MainActor in
                    appModel.immersiveSpaceState = .inTransition
                }
                layerRenderer.waitUntilRunning()
                continue
            } else {
                Task { @MainActor in
                    if appModel.immersiveSpaceState != .open {
                        appModel.immersiveSpaceState = .open
                    }
                }
                autoreleasepool {
                    self.renderFrame()
                }
            }
        }
    }
}

// Generic matrix math utility functions
func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    return matrix_float4x4.init(columns:(vector_float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
                                         vector_float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
                                         vector_float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
                                         vector_float4(                  0,                   0,                   0, 1)))
}

func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(1, 0, 0, 0),
                                         vector_float4(0, 1, 0, 0),
                                         vector_float4(0, 0, 1, 0),
                                         vector_float4(translationX, translationY, translationZ, 1)))
}

func matrix4x4_scale(_ scaleX: Float, _ scaleY: Float, _ scaleZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(scaleX, 0, 0, 0),
                                         vector_float4(0, scaleY, 0, 0),
                                         vector_float4(0, 0, scaleZ, 0),
                                         vector_float4(0, 0, 0, 1)))
}

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}

// Extension to extract xyz components from SIMD4
extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
}

