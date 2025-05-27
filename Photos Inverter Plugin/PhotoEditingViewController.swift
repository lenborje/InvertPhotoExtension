//
//  PhotoEditingViewController.swift
//  Photos Project Inverter
//
//  Created by Lennart Börjeson on 2025-03-11.
//  Copyright © 2025 Lennart Börjeson. All rights reserved.
//

import AppKit
import PhotosUI
import CoreImage

class PhotoEditingViewController: NSViewController, PHContentEditingController {
    
    // Variabel för att lagra originalbilden
    var inputImage: NSImage?
    var contentEditingInput: PHContentEditingInput?
    
    @IBOutlet weak var previewImageView: NSImageView!
    // MARK: - PHContentEditingController
    
    
    @IBOutlet weak var autoContrast: NSButton!
    @IBOutlet weak var blackPoint: NSSlider!
    @IBOutlet weak var whitePoint: NSSlider!
    
    @IBAction func autoContrastAction(_ sender: NSButton) {
        updatePreviewImage()
    }
    @IBAction func blackPointAction(_ sender: NSSlider) {
        if (blackPoint.floatValue > whitePoint.floatValue) {
            blackPoint.floatValue = whitePoint.floatValue
        }
        updatePreviewImage()
    }
    @IBAction func whitePointAction(_ sender: NSSlider) {
        if (whitePoint.floatValue < blackPoint.floatValue) {
            whitePoint.floatValue = blackPoint.floatValue
        }
        updatePreviewImage()
    }
    
    
    // Kontrollera om vi kan hantera tidigare sparade justeringsdata (här returnerar vi alltid false)
    func canHandle(_ adjustmentData: PHAdjustmentData) -> Bool {
        // Försök att tolka adjustmentData.data som en sträng (om det är giltigt UTF8)
        let dataString = String(data: adjustmentData.data, encoding: .utf8) ?? "Ogiltig UTF8-data"
        print("[DEBUG] canHandle called with adjustmentData:")
        print("         formatIdentifier: \(adjustmentData.formatIdentifier)")
        print("         formatVersion: \(adjustmentData.formatVersion)")
        print("         data: \(dataString)")
        
        // Returnera false för att indikera att vi inte kan hantera denna adjustmentData
        // Detta gör att Photos ger oss den nuvarande builden i fullSizeImageURL istället för originalet
        return false
    }
    
    // Starta redigeringen med indata från Photos-appen
    func startContentEditing(with contentEditingInput: PHContentEditingInput, placeholderImage: NSImage) {
        self.contentEditingInput = contentEditingInput
        // Försök att läsa in den fullstorlekbild som ska redigeras
        if let url = contentEditingInput.fullSizeImageURL {
            inputImage = NSImage(contentsOf: url)
            if let loadedImage = inputImage {
                print("[DEBUG] Successfully loaded image from \(url). Size: \(loadedImage.size)")
                // Försök invertera bilden för att visa en preview
                autoContrast.state = .on
                if let invertedPreview = processImage(loadedImage) {
                    previewImageView.image = invertedPreview
                    print("[DEBUG] Preview image updated with inverted image.")
                    autoContrast.state = .off
                    whitePoint.isEnabled = true
                    blackPoint.isEnabled = true
                } else {
                    print("[DEBUG] Inversion for preview failed.")
                    // Visa originalbilden om inversion misslyckas
                    previewImageView.image = loadedImage
                }
            } else {
                print("[DEBUG] Failed to load image from \(url)")
            }
        }
    }
    
    // När redigeringen är klar sparas resultatet
    func finishContentEditing(completionHandler: @escaping ((PHContentEditingOutput?) -> Void)) {
        guard let input = self.contentEditingInput else {
            completionHandler(nil)
            return
        }
        print("[DEBUG] finishContentEditing called with contentEditingInput: \(input)")
        let output = PHContentEditingOutput(contentEditingInput: input)
        print("[DEBUG] Created PHContentEditingOutput with output URL: \(output.renderedContentURL)")
        
        if let inputImage = inputImage,
           let processedImage = processImage(inputImage) {
            // spara processedImage till output.renderedContentURL... {
            print("[DEBUG] Image inversion succeeded. Inverted image size: \(processedImage.size)")
            // Använd den fil-URL som output.renderedContentURL tillhandahåller
            let outputURL = output.renderedContentURL
            let directoryURL = outputURL.deletingLastPathComponent()
            
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                print("[DEBUG] Ensured directory exists at: \(directoryURL)")
            } catch {
                print("Failed to create directory: \(error)")
            }
            
            // Försök att hämta en CGImage-representation från den inverterade bilden
            if let cgImage = processedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                print("[DEBUG] Successfully retrieved CGImage from inverted image.")
                let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
                if let data = bitmapRep.representation(using: .jpeg, properties: [:]) {
                    do {
                        try data.write(to: outputURL)
                        print("[DEBUG] Successfully wrote output file to: \(outputURL)")
                        let adjustmentInfo: [String: Any] = ["inversion": true]
                        let adjustmentData = try? JSONSerialization.data(withJSONObject: adjustmentInfo, options: [])
                        output.adjustmentData = PHAdjustmentData(formatIdentifier: "se.lenborje.inverter", formatVersion: "1.0", data: adjustmentData ?? Data())
                    } catch {
                        print("Fel vid skrivning av fil: \(error)")
                    }
                } else {
                    print("[DEBUG] Failed to generate JPEG data from bitmap representation.")
                }
            } else {
                print("[DEBUG] Failed to retrieve CGImage from inverted image.")
            }
        } else {
            print("[DEBUG] Failed to invert image or input image is nil.")
        }
        
        completionHandler(output)
    }
    
    // Hantera avbruten redigering (rensa eventuella resurser)
    func cancelContentEditing() {
        // Rensa upp om det behövs
    }
    
    var shouldShowCancelConfirmation: Bool {
        return false
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        blackPoint.isContinuous = true
        whitePoint.isContinuous = true
    }
    
    // MARK: - Bildinvertering
    
    
    func processImage(_ image: NSImage) -> NSImage? {
        guard let inverted = invertImage(image) else { return nil }

        let useSliders = (autoContrast.state == .off)
        blackPoint.isEnabled = useSliders
        whitePoint.isEnabled = useSliders

        var black = CGFloat(blackPoint.floatValue) / 100.0
        var white = CGFloat(whitePoint.floatValue) / 100.0


        if autoContrast.state == .on {
            if let (autoBlack, autoWhite) = computeLuminanceExtremes(from: inverted) {
                black = autoBlack
                white = autoWhite
                blackPoint.floatValue = Float(black * 100)
                whitePoint.floatValue = Float(white * 100)
            }
        }

        if white > black {
            return applyBlackWhitePoint(to: inverted, blackPoint: black, whitePoint: white)
        } else {
            return inverted
        }
    }
    
    
    
    /// Använder Core Image för att invertera en bild
    func invertImage(_ image: NSImage) -> NSImage? {
        // Try to get a CGImage representation of the NSImage
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        // Create a CIImage from the CGImage
        let ciImage = CIImage(cgImage: cgImage)
        
        // Initialize the CIColorInvert filter
        guard let filter = CIFilter(name: "CIColorInvert") else { return nil }
        filter.setDefaults()
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        
        // Get the output CIImage from the filter
        guard let outputCIImage = filter.outputImage else { return nil }
        
        // Render the output CIImage into a CGImage
        let context = CIContext(options: nil)
        guard let outputCGImage = context.createCGImage(outputCIImage, from: outputCIImage.extent) else { return nil }
        
        // Create and return a new NSImage using the rendered CGImage
        return NSImage(cgImage: outputCGImage, size: image.size)
    }
    
    
    func applyBlackWhitePoint(to image: NSImage, blackPoint: CGFloat, whitePoint: CGFloat) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        
        // Begränsa till rimliga värden
        let black = min(max(blackPoint, 0.0), 1.0)
        let white = min(max(whitePoint, 0.0), 1.0)
        
        guard white > black else { return image } // Skydd mot omvänt intervall
        
        // Linjär skala: vi vill transformera [black, white] → [0,1]
        let slope = 1.0 / (white - black)
        let bias = -black * slope
        
        let colorMatrixFilter = CIFilter(name: "CIColorMatrix")!
        colorMatrixFilter.setValue(ciImage, forKey: kCIInputImageKey)
        
        // Ställ in r, g, b kanaler individuellt – samma lutning/bias för varje
        let vector = CIVector(x: slope, y: 0, z: 0, w: bias)
        colorMatrixFilter.setValue(vector, forKey: "inputRVector")
        colorMatrixFilter.setValue(vector, forKey: "inputGVector")
        colorMatrixFilter.setValue(vector, forKey: "inputBVector")
        // Alpha-kanalen oförändrad
        colorMatrixFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        
        guard let output = colorMatrixFilter.outputImage else { return nil }
        
        let context = CIContext()
        guard let outCGImage = context.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: outCGImage, size: image.size)
    }
    
    func computeLuminanceExtremes(from image: NSImage) -> (CGFloat, CGFloat)? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        
        let extent = ciImage.extent
        let inputExtent = CIVector(x: extent.origin.x, y: extent.origin.y, z: extent.size.width, w: extent.size.height)
        
        // Skapa filter för minimum
        guard let minFilter = CIFilter(name: "CIAreaMinimum"),
              let maxFilter = CIFilter(name: "CIAreaMaximum") else { return nil }
        
        minFilter.setValue(ciImage, forKey: kCIInputImageKey)
        minFilter.setValue(inputExtent, forKey: kCIInputExtentKey)
        
        maxFilter.setValue(ciImage, forKey: kCIInputImageKey)
        maxFilter.setValue(inputExtent, forKey: kCIInputExtentKey)
        
        let context = CIContext()
        
        func luminance(from pixel: [UInt8]) -> CGFloat {
            let r = CGFloat(pixel[0]) / 255.0
            let g = CGFloat(pixel[1]) / 255.0
            let b = CGFloat(pixel[2]) / 255.0
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        
        func extractPixel(from ciImage: CIImage) -> [UInt8]? {
            guard let cgImage = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: 1, height: 1)) else { return nil }
            let bytesPerPixel = 4
            var pixelData = [UInt8](repeating: 0, count: bytesPerPixel)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapContext = CGContext(data: &pixelData, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: bytesPerPixel,
                                          space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            bitmapContext?.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return pixelData
        }
        
        guard let minPixel = extractPixel(from: minFilter.outputImage!),
              let maxPixel = extractPixel(from: maxFilter.outputImage!) else { return nil }
        
        let minLum = luminance(from: minPixel)
        let maxLum = luminance(from: maxPixel)
        
        return (minLum, maxLum)
    }
    
    func updatePreviewImage() {
        guard let original = inputImage else { return }

        if let result = processImage(original) {
            previewImageView.image = result
        }
    }}
