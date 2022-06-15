//
//  GrayFilterKernel.ci.metal
//  RawCam2
//
//  Created by thilina shashimal senarath on 2022-06-11.
//

#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

extern "C"{
    namespace coreimage{
        float4 grayFilterKernel(sample_t s) {
          float gray = (s.r + s.g + s.b) / 3;
          return float4(gray, gray, gray, s.a);
        }
    }
}
