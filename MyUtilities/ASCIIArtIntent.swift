import AppIntents
import UIKit

enum ConversionError: CustomNSError {
    case invalidImageData
    case imageRenderingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidImageData: return "Could not load valid image data."
        case .imageRenderingFailed: return "Failed to render ASCII art to image."
        }
    }
}

struct ASCIIArtIntent: AppIntent {
    static var title: LocalizedStringResource = "Convert Image to ASCII Art"
    static var description = IntentDescription("Analyzes the selected image and converts it into ASCII art text.")
    
    static var openAppWhenRun: Bool = false
    
    @Parameter(title: "Input Image")
    var inputImage: IntentFile

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard let uiImage = UIImage(data: inputImage.data) else {
            throw ConversionError.invalidImageData
        }
        
        let asciiArtText = convertToASCII(image: uiImage)
        
        guard let renderedImage = renderTextToImage(text: asciiArtText) else {
            throw ConversionError.imageRenderingFailed
        }
        
        guard let pngData = renderedImage.pngData() else {
            throw ConversionError.imageRenderingFailed
        }
        
        let intentFile = IntentFile(data: pngData, filename: "ascii_art.png", type: .png)
        
        return .result(value: intentFile)
    }
}

extension ASCIIArtIntent {
    private func renderTextToImage(text: String) -> UIImage? {
        let fontSize: CGFloat = 10.0
        let font = UIFont(name: "Menlo-Regular", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]

        let attributedText = NSAttributedString(string: text, attributes: attributes)
            
        let rect = attributedText.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
        
        let size = CGSize(width: ceil(rect.width), height: ceil(rect.height))
        
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            attributedText.draw(at: .zero)
        }
        return image
    }
    
    func convertToASCII(image: UIImage) -> String {
        let targetWidth: Int = 100
        
        guard let cgImage = image.cgImage,
             let resizedImage = resizeImage(cgImage, toWidth: targetWidth),
             let pixelData = resizedImage.dataProvider?.data,
             let data: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData)
        else {
            return "An error occurred during conversion."
        }
        
        let width = resizedImage.width
        let height = resizedImage.height
        let bytesPerPixel = resizedImage.bitsPerPixel / 8
        
        let asciiRamp = "$@B%8&WM#*oahkbdpqwmZO0QLCJUYXzcvunxrjft/\\|()1{}[]?-_+~<>i!lI;:,\"^`      "
        let rampChars = Array(asciiRamp)
        let rampLength = rampChars.count
        
        var asciiArt = ""
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                
                let r = Double(data[offset])
                let g = Double(data[offset + 1])
                let b = Double(data[offset + 2])
                
                let gray = 0.299 * r + 0.587 * g + 0.114 * b
                
                let charIndex = Int(gray * Double(rampLength) / 256.0)
                
                if charIndex < rampLength {
                    asciiArt.append(rampChars[charIndex])
                } else {
                    asciiArt.append(rampChars[rampLength - 1])
                }
            }
            asciiArt.append("\n") 
        }
        
        return asciiArt
    }
    
    private func resizeImage(_ cgImage: CGImage, toWidth targetWidth: Int) -> CGImage? {
        let originalWidth = cgImage.width
        let originalHeight = cgImage.height
        
        let targetHeight = Int(Double(originalHeight) * Double(targetWidth) / Double(originalWidth))
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        
        guard let context = CGContext(data: nil,
                                      width: targetWidth,
                                      height: targetHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: targetWidth * 4,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
            return nil
        }
        
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        
        return context.makeImage()
    }
}
