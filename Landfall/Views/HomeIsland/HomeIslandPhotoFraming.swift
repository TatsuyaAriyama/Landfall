import Foundation

/// SceneKit uses a horizontal field of view on the island. Keep a subject's
/// framing consistent on the short side of portrait and landscape viewports.
enum HomeIslandPhotoFraming {
    struct Lens {
        var horizontalFieldOfView: Float
        var radius: Float
    }

    static func lens(subjectRadius: Float, aspectRatio: Float) -> Lens {
        let aspect = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1
        let halfAngle: Float = 24 * .pi / 180
        let horizontalHalfAngle = atan(tan(halfAngle) * max(1, aspect))
        return Lens(
            horizontalFieldOfView: horizontalHalfAngle * 360 / .pi,
            // A sphere's silhouette subtends asin(r / distance); a small
            // margin keeps the edge clear of the frame in either orientation.
            radius: max(3.2, subjectRadius / sin(halfAngle) * 1.08)
        )
    }
}
