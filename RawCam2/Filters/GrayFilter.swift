//
//  GrayFilter.swift
//  RawCam2
//
//  Created by thilina shashimal senarath on 2022-06-11.
//

import Foundation
import CoreImage

class GrayFilter:CIFilter{
    var inputImage:CIImage?

        
    static var kernel: CIKernel = { () -> CIColorKernel in
      guard let url = Bundle.main.url(
        forResource: "GrayFilterKernel.ci",
        withExtension: "metallib"),
        let data = try? Data(contentsOf: url) else {
        fatalError("Unable to load metallib")
      }

      guard let kernel = try? CIColorKernel(
        functionName: "grayFilterKernel",
        fromMetalLibraryData: data) else {
        fatalError("Unable to create color kernel")
      }

      return kernel
    }()
    
    override var outputImage: CIImage? {
      guard let inputImage = inputImage else { return nil }
      return GrayFilter.kernel.apply(
        extent: inputImage.extent,
        roiCallback: { _, rect in
          return rect
        },
        arguments: [inputImage])
    }
}
