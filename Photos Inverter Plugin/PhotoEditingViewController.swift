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
    
    // MARK: - PHContentEditingController
    
    // Kontrollera om vi kan hantera tidigare sparade justeringsdata (här returnerar vi alltid true)
    func canHandle(_ adjustmentData: PHAdjustmentData) -> Bool {
        return true
    }
    
    // Starta redigeringen med indata från Photos-appen
    func startContentEditing(with contentEditingInput: PHContentEditingInput, placeholderImage: NSImage) {
        self.contentEditingInput = contentEditingInput
        // Försök att läsa in den fullstorlekbild som ska redigeras
        if let url = contentEditingInput.fullSizeImageURL {
            inputImage = NSImage(contentsOf: url)
            // Här kan du visa bilden i ett gränssnitt om du vill låta användaren se effekten i realtid
        }
    }
    
    // När redigeringen är klar sparas resultatet
    func finishContentEditing(completionHandler: @escaping ((PHContentEditingOutput?) -> Void)) {
        guard let input = self.contentEditingInput else {
            completionHandler(nil)
            return
        }
        let output = PHContentEditingOutput(contentEditingInput: input)
        
        // Om vi har en giltig bild, applicera inverteringseffekten
        if let inputImage = inputImage, let invertedImage = invertImage(inputImage) {
            // Använd den fil-URL som output.renderedContentURL tillhandahåller
            let outputURL = output.renderedContentURL
            let directoryURL = outputURL.deletingLastPathComponent()

            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Failed to create directory: \(error)")
            }

            // Försök att hämta en CGImage-representation från den inverterade bilden
            if let cgImage = invertedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
                if let data = bitmapRep.representation(using: .jpeg, properties: [:]) {
                    do {
                        try data.write(to: outputURL)
                        // Spara en enkel, tom justeringsdata. I ett produktionsscenario kan du spara mer information om redigeringen.
                        output.adjustmentData = PHAdjustmentData(formatIdentifier: "se.lenborje.inverter", formatVersion: "1.0", data: Data())
                    } catch {
                        print("Fel vid skrivning av fil: \(error)")
                    }
                }
            } else {
                print("Kunde inte hämta CGImage från den inverterade bilden")
            }
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
