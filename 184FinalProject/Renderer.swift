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
        self.layerRenderer = layerRenderer
        self.device = layerRenderer.device
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
    private var sampleCount: UInt32 = 0
    private var lastFrameTime: Double = 0
    private var isMoving: Bool = false
    private var tileDataBuffer: MTLBuffer?
    private var needsReset: Bool = true
    
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
        
        // Create tile-specific accumulation kernel
        if let function = library.makeFunction(name: "tileAccumulationKernel") {
            do {
                let pipeline = try device.makeComputePipelineState(function: function)
                computePipelines["tileAccumulationKernel"] = pipeline
            } catch {
                print("Failed to create compute pipeline for tileAccumulationKernel: \(error)")
            }
        }
    }
    
    private func createComputeOutputTexture(width: Int, height: Int) {
        // Create three textures with the same descriptor setup
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
        
        // Create textures
        computeOutputTexture = createTexture()       // Final output texture shown to the user
        pathTracerOutputTexture = createTexture()    // Single sample from pathTracer
        accumulationTexture = createTexture()        // Accumulated results
        
        // Create tile data buffer
        createTileDataBuffer(width: width, height: height)
        
        // Reset sample count when creating new textures
        resetAccumulation()
    }
    
    private func createTileDataBuffer(width: Int, height: Int) {
        // Calculate number of tiles
        let tileSize = 16
        let tilesWide = (width + tileSize - 1) / tileSize
        let tilesHigh = (height + tileSize - 1) / tileSize
        let totalTiles = tilesWide * tilesHigh
        
        // Create buffer for tile data
        let bufferSize = MemoryLayout<TileData>.stride * totalTiles
        tileDataBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
        tileDataBuffer?.label = "TileDataBuffer"
        
        // Initialize tile data
        initializeTileData(tilesWide: tilesWide, tilesHigh: tilesHigh)
    }
    
    private func initializeTileData(tilesWide: Int, tilesHigh: Int) {
        guard let tileDataPtr = tileDataBuffer?.contents() else { return }
        
        let totalTiles = tilesWide * tilesHigh
        let tileDataArray = UnsafeMutableBufferPointer<TileData>(
            start: tileDataPtr.bindMemory(to: TileData.self, capacity: totalTiles),
            count: totalTiles
        )
        
        // Initialize each tile
        for i in 0..<totalTiles {
            var tileData = TileData()
            tileData.accumulatedColor = SIMD4<Float>(0, 0, 0, 0)
            tileData.sampleCount = 0
            tileData.tileIndex = UInt32(i)
            tileData.needsReset = true
            
            // Optional: Set tile bounds for spatial culling (not used in this implementation)
            tileData.minBounds = SIMD3<Float>(-Float.infinity, -Float.infinity, -Float.infinity)
            tileData.maxBounds = SIMD3<Float>(Float.infinity, Float.infinity, Float.infinity)
            
            tileDataArray[i] = tileData
        }
    }
    
    private func resetAccumulation() {
        sampleCount = 0
        print("Resetting accumulation buffer")
        
        // Reset all tile data
        markAllTilesForReset()
        
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
    
    private func markAllTilesForReset() {
        guard let tileDataPtr = tileDataBuffer?.contents(),
              let outputTexture = computeOutputTexture else { return }
        
        let width = outputTexture.width
        let height = outputTexture.height
        let tileSize = 16
        let tilesWide = (width + tileSize - 1) / tileSize
        let tilesHigh = (height + tileSize - 1) / tileSize
        let totalTiles = tilesWide * tilesHigh
        
        let tileDataArray = UnsafeMutableBufferPointer<TileData>(
            start: tileDataPtr.bindMemory(to: TileData.self, capacity: totalTiles),
            count: totalTiles
        )
        
        // Mark all tiles for reset
        for i in 0..<totalTiles {
            tileDataArray[i].needsReset = true
            tileDataArray[i].sampleCount = 0
        }
        
        // Global flag to indicate reset needed
        needsReset = true
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
        // MARK: set the tile data buffer for direct access in the fragment shader
        renderEncoder.setFragmentBuffer(tileDataBuffer, offset: 0, index: BufferIndex.tileData.rawValue)
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
                  let tileAccumPipeline = computePipelines["tileAccumulationKernel"],
                  let outputTexture = computeOutputTexture,
                  let pathTracerOutput = pathTracerOutputTexture,
                  let accumTexture = accumulationTexture,
                  let tileDataBuffer = tileDataBuffer else {
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
            lastCameraPosition = currentCameraPosition
            sampleCount += 1
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
                fovY: fovY
            )
            
            // Calculate tile-based threadgroups and threads
            let tileSize = 16
            let threadsPerTile = MTLSize(width: tileSize, height: tileSize, depth: 1)
            let tilesWide = (outputTexture.width + tileSize - 1) / tileSize
            let tilesHigh = (outputTexture.height + tileSize - 1) / tileSize
            let tileCount = MTLSize(width: tilesWide, height: tilesHigh, depth: 1)
            
            // Define the size of threadgroup memory needed for tiles
            let tileOutputSize = MemoryLayout<TileOutput>.stride
            
            // Standard threadgroups for full screen passes
            let standardThreads = MTLSize(width: 32, height: 8, depth: 1)
            let standardGroups = MTLSize(
                width: (outputTexture.width + standardThreads.width - 1) / standardThreads.width,
                height: (outputTexture.height + standardThreads.height - 1) / standardThreads.height,
                depth: 1
            )
            
            // PASS 1: Path Tracer - process pixels
            guard let pathTracerEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
            pathTracerEncoder.setComputePipelineState(pathTracerPipeline)
            pathTracerEncoder.setBytes(&params, length: MemoryLayout<ComputeParams>.size, index: 0)
            pathTracerEncoder.setBuffer(tileDataBuffer, offset: 0, index: BufferIndex.tileData.rawValue)
            pathTracerEncoder.setTexture(pathTracerOutput, index: 0) // Write to the pathTracer output texture
            
            // Use simplified dispatching initially
            pathTracerEncoder.setThreadgroupMemoryLength(tileOutputSize, index: ThreadgroupIndex.tileData.rawValue)
            pathTracerEncoder.dispatchThreadgroups(standardGroups, threadsPerThreadgroup: standardThreads)
            pathTracerEncoder.endEncoding()
            
            // PASS 2: Simple accumulation pass
            guard let accumEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
            accumEncoder.setComputePipelineState(accumulationPipeline)
            accumEncoder.setBytes(&sampleCount, length: MemoryLayout<UInt32>.size, index: 0)
            accumEncoder.setBuffer(tileDataBuffer, offset: 0, index: BufferIndex.tileData.rawValue)
            accumEncoder.setTexture(pathTracerOutput, index: 0)   // Current frame
            accumEncoder.setTexture(accumTexture, index: 1)       // Accumulated frames
            accumEncoder.setTexture(outputTexture, index: 2)      // Output for display
            
            // Simplified dispatch for now
            accumEncoder.dispatchThreadgroups(standardGroups, threadsPerThreadgroup: standardThreads)
            accumEncoder.endEncoding()
            
            // Copy accumulated result back for next frame
            guard let copyEncoder = commandBuffer.makeBlitCommandEncoder() else { return }
            copyEncoder.copy(from: outputTexture, to: accumTexture)
            copyEncoder.endEncoding()
            
            print("Rendering sample \(sampleCount), tiles: \(tilesWide)×\(tilesHigh)")
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

