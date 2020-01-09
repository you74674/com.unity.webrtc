#pragma once
#include "Codec/IEncoder.h"
#include "GraphicsDevice/IGraphicsDevice.h"
#include <VideoToolbox/VideoToolbox.h>

namespace WebRTC {
    class VTEncoderMetal : public IEncoder {
    public:
        VTEncoderMetal(uint32_t nWidth, uint32_t nHeight, IGraphicsDevice* device);
        ~VTEncoderMetal();
        void InitV() override;   //Can throw exception.
        void SetRate(uint32_t rate) override;
        void UpdateSettings() override;
        bool CopyBuffer(void* srcNativeTexture) override;
        bool EncodeFrame() override;
        bool IsSupported() const override;
        void SetIdrFrame() override;
        uint64 GetCurrentFrameCount() const override { return frameCount; }
        CodecInitializationResult GetCodecInitializationResult() const override { return CodecInitializationResult::Success; }
        
    void OnVTCompressionOutput(std::vector<uint8>* workBuffer, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef compressedBufferFromVT);
    private:
        uint64 frameCount = 0;
        uint64 m_width = 0;
        uint64 m_height = 0;
        IGraphicsDevice* m_device;
        ITexture2D* m_renderTextures[bufferedFrameNum];         // m_renderTextures is receiver of Unity's render frame
        CVPixelBufferRef m_pixelBuffers[bufferedFrameNum];      // m_pixelBuffers is a buffers VT access to compress image. Natively refered by m_renderTextures
        std::vector<uint8> m_workBuffers[bufferedFrameNum];     // m_workBuffers is a buffer to bring the image to WebRTC

        VTCompressionSessionRef encoderSession;
    };
}
