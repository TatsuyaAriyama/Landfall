import Foundation

@main
private enum HomeIslandPhotoFramingProbe {
    static func main() {
        let subjectRadii: [Float] = [1.8, 4.7, 14.8, 14.8 * 1.12]
        for aspect: Float in [0.45, 0.75, 1, 1.33, 2.22] {
            for subjectRadius in subjectRadii {
                let lens = HomeIslandPhotoFraming.lens(
                    subjectRadius: subjectRadius,
                    aspectRatio: aspect
                )
                let halfHorizontal = lens.horizontalFieldOfView * .pi / 360
                let halfVertical = atan(tan(halfHorizontal) / aspect)
                let subjectHalfAngle = asin(subjectRadius / lens.radius)
                precondition(subjectHalfAngle < min(halfHorizontal, halfVertical),
                             "The subject was cropped in viewport aspect \(aspect)")
                precondition(lens.radius >= 3.2 && lens.radius <= 48,
                             "A preset exceeded the photo camera's radius limits")
                precondition(abs(min(halfHorizontal, halfVertical) - 24 * .pi / 180) < 0.00001,
                             "Portrait and landscape subject sizes differed")
            }
        }
        for invalidAspect: Float in [0, -1, .nan, .infinity] {
            let lens = HomeIslandPhotoFraming.lens(subjectRadius: 14.8, aspectRatio: invalidAspect)
            precondition(lens.radius.isFinite && lens.horizontalFieldOfView.isFinite,
                         "An unmeasured viewport produced an invalid camera")
        }
        print("PASS island/navigator/jetty framing in portrait, landscape, expanded island, and unmeasured viewport")
    }
}
