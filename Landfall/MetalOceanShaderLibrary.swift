import Metal

/// Preflights the native ocean program before SceneKit switches away from its
/// shader-modifier fallback. Keeping this check separate makes each migration
/// step reversible and prevents a missing metallib symbol from blanking the sea.
enum MetalOceanShaderLibrary {
    static let vertexFunctionName = "landfallOceanVertex"
    static let fragmentFunctionName = "landfallOceanFragment"

    static func isAvailable(on device: MTLDevice) -> Bool {
        makeLibrary(on: device) != nil
    }

    static func makeLibrary(on device: MTLDevice) -> MTLLibrary? {
        guard let library = device.makeDefaultLibrary(),
              library.makeFunction(name: vertexFunctionName) != nil,
              library.makeFunction(name: fragmentFunctionName) != nil else {
            return nil
        }
        return library
    }
}
