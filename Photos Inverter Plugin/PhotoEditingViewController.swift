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
                if let invertedPreview = invertImage(loadedImage) {
                    previewImageView.image = invertedPreview
                    print("[DEBUG] Preview image updated with inverted image.")
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
        
        if let inputImage = inputImage, let invertedImage = invertImage(inputImage) {
            print("[DEBUG] Image inversion succeeded. Inverted image size: \(invertedImage.size)")
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
            if let cgImage = invertedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
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
    
    // MARK: - Bildinvertering
    
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
}
