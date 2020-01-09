#include "pch.h"
#include "Codec/VideoToolbox/VTEncoderMetal.h"
#include "GraphicsDevice/IGraphicsDevice.h"
#include "GraphicsDevice/ITexture2D.h"
#include "GraphicsDevice/Metal/MetalGraphicsDevice.h"

#include <libkern/OSByteOrder.h>

namespace WebRTC {

using webrtc::H264::kAud;
using webrtc::H264::kSps;
using webrtc::H264::NaluIndex;
using webrtc::H264::NaluType;
using webrtc::H264::ParseNaluType;

const char kAnnexBHeaderBytes[4] = {0, 0, 0, 1};
const size_t kAvccHeaderByteSize = sizeof(uint32_t);


class VTFrameBuffer : public webrtc::VideoFrameBuffer
{
public:
//    std::vector<uint8>& buffer;
    std::unique_ptr<rtc::Buffer> buffer;
    
    VTFrameBuffer(int width, int height, std::unique_ptr<rtc::Buffer>& data) : buffer(std::move(data)), frameWidth(width), frameHeight(height)  {}
    
    //webrtc::VideoFrameBuffer pure virtual functions
    // This function specifies in what pixel format the data is stored in.
    virtual Type type() const override
    {
        //fake I420 to avoid ToI420() being called
        //        return Type::kI420;
        return Type::kI420;
    }
    // The resolution of the frame in pixels. For formats where some planes are
    // subsampled, this is the highest-resolution plane.
    virtual int width() const override
    {
        return frameWidth;
    }
    virtual int height() const override
    {
        return frameHeight;
    }
    // Returns a memory-backed frame buffer in I420 format. If the pixel data is
    // in another format, a conversion will take place. All implementations must
    // provide a fallback to I420 for compatibility with e.g. the internal WebRTC
    // software encoders.
    virtual rtc::scoped_refptr<webrtc::I420BufferInterface> ToI420() override
    {
        return nullptr;
    }
    
private:
    int frameWidth;
    int frameHeight;
};

// Convenience function for creating a dictionary.
inline static CFDictionaryRef CreateCFDictionary(CFTypeRef* keys,
                                                 CFTypeRef* values,
                                                 size_t size)
{
    return CFDictionaryCreate(kCFAllocatorDefault, keys, values, size,
                              &kCFTypeDictionaryKeyCallBacks,
                              &kCFTypeDictionaryValueCallBacks);
}



//    class H264Info
//    {
//        friend H264Info* ParseSampleBuffer(CMSampleBufferRef sampleBuffer, std::vector<uint8_t>& encodedFrame);
//
//        public:
//            H264Info() {};
//            bool IsKeyFrame() { return isKeyFrame; }
//        private:
//            bool isKeyFrame;
//            int nalUnitHeaderLengthOut = 0;
//            size_t parameterSetCountOut = 0;
//            size_t naluOffset = 0;
//            std::vector<const uint8_t*> params;
//            std::vector<size_t> paramSizes;
//            CMBlockBufferRef blockBuffer;
//            size_t sizeBlockBuffer;
//    };

//H264Info* ParseSampleBuffer(CMSampleBufferRef sampleBuffer, std::vector<uint8_t>& encodedFrame)
//{
//    const char kAnnexBHeaderBytes[4] = {0, 0, 0, 1};
//    auto info = std::make_unique<H264Info>();
//    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
//    if(attachments != nullptr && CFArrayGetCount(attachments))
//    {
//        CFDictionaryRef attachment = static_cast<CFDictionaryRef>(CFArrayGetValueAtIndex(attachments, 0));
//        info->isKeyFrame = !CFDictionaryContainsKey(attachment, kCMSampleAttachmentKey_NotSync);
//    }
//
//    CMVideoFormatDescriptionRef description =
//    CMSampleBufferGetFormatDescription(sampleBuffer);
//
//    OSStatus status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, 0, nullptr, nullptr, &info->parameterSetCountOut, &info->nalUnitHeaderLengthOut);
//    if (status != noErr)
//    {
//        NSLog(@"VTCompressionOutputCallback CMVideoFormatDescriptionGetH264ParameterSetAtIndex returns failed %d", status);
//        return nullptr;
//    }
//
//    if(info->isKeyFrame)
//    {
//        for(size_t i = 0; i < info->parameterSetCountOut; i++)
//        {
//            size_t parameterSetSizeOut = 0;
//            const uint8_t* parameterSetPointerOut = nullptr;
//
//            status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, i, &parameterSetPointerOut, &parameterSetSizeOut, nullptr, nullptr);
//            if (status != noErr)
//            {
//                NSLog(@"VTCompressionOutputCallback CMVideoFormatDescriptionGetH264ParameterSetAtIndex returns failed %d", status);
//                return nullptr;
//            }
//            encodedFrame.insert(encodedFrame.end(), std::begin(kAnnexBHeaderBytes), std::end(kAnnexBHeaderBytes));
//            encodedFrame.insert(encodedFrame.end(), parameterSetPointerOut, parameterSetPointerOut + parameterSetSizeOut);
//        }
//    }
//    info->blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
//    if(info->blockBuffer == nullptr)
//    {
//        NSLog(@"VTCompressionOutputCallback CMSampleBufferGetDataBuffer is failed");
//        return nullptr;
//    }
//    if (!CMBlockBufferIsRangeContiguous(info->blockBuffer, 0, 0))
//    {
//        NSLog(@"VTCompressionOutputCallback block buffer is not contiguous.");
//        return nullptr;
//    }
//    info->sizeBlockBuffer = CMBlockBufferGetDataLength(info->blockBuffer);
//
//    //auto sizeHeader = encodedFrame.size();
//    //encodedFrame.resize(sizeHeader + info->sizeBlockBuffer);
//    uint8_t* dataPointerOut = nullptr;
//    status = CMBlockBufferGetDataPointer(info->blockBuffer, 0, nullptr, nullptr, (char **)(&dataPointerOut));
//    if (status != noErr)
//    {
//        NSLog(@"VTCompressionOutputCallback CMBlockBufferGetDataLength is failed");
//        return nullptr;
//    }
//    //auto sizeEncodedFrame = encodedFrame.size();
//    auto remaining = info->sizeBlockBuffer;
//    while(remaining > 0)
//    {
//        auto nalUnitSize = *(uint32_t*)(dataPointerOut);
//        nalUnitSize = OSSwapBigToHostInt(nalUnitSize);
//        auto nalUnitStart = dataPointerOut + info->nalUnitHeaderLengthOut;
//        encodedFrame.insert(encodedFrame.end(), std::begin(kAnnexBHeaderBytes), std::end(kAnnexBHeaderBytes));
//        encodedFrame.insert(encodedFrame.end(), nalUnitStart, nalUnitStart + nalUnitSize);
//
//        auto sizeWritten = nalUnitSize + info->nalUnitHeaderLengthOut;
//        remaining -= sizeWritten;
//        dataPointerOut += sizeWritten;
//    }
//    if(remaining != 0)
//    {
//        NSLog(@"VTCompressionOutputCallback block buffer is broken");
//        return nullptr;
//    }
//    return info.release();
//}

void PrepareEncodedFrame(CMSampleBufferRef sampleBuffer, std::vector<uint8_t>& encodedFrame)
{
    const char kAnnexBHeaderBytes[4] = {0, 0, 0, 1};
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    bool isKeyFrame = false;
    if(attachments != nullptr && CFArrayGetCount(attachments))
    {
        CFDictionaryRef attachment = static_cast<CFDictionaryRef>(CFArrayGetValueAtIndex(attachments, 0));
        isKeyFrame = !CFDictionaryContainsKey(attachment, kCMSampleAttachmentKey_NotSync);
    }
    
    CMVideoFormatDescriptionRef description =
    CMSampleBufferGetFormatDescription(sampleBuffer);
    
    kCMPixelFormat_32BGRA;
    
    size_t parameterSetCount = 0;
    int szNalUnitHeader = 0;
    size_t naluOffset = 0;
    //    std::vector<const uint8_t*> params;
    //    std::vector<size_t> paramSizes;
    
    OSStatus status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, 0, nullptr, nullptr, &parameterSetCount, &szNalUnitHeader);
    if (status != noErr)
    {
        NSLog(@"VTCompressionOutputCallback CMVideoFormatDescriptionGetH264ParameterSetAtIndex returns failed %d", status);
        return;
    }
    
    if(isKeyFrame)
    {
        for(size_t i = 0; i < parameterSetCount; ++i)
        {
            size_t szParamSet = 0;
            const uint8_t* pParamSet = nullptr;
            
            status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, i, &pParamSet, &szParamSet, nullptr, nullptr);
            if (status != noErr)
            {
                NSLog(@"VTCompressionOutputCallback CMVideoFormatDescriptionGetH264ParameterSetAtIndex returns failed %d", status);
                return;
            }
            encodedFrame.insert(encodedFrame.end(), std::begin(kAnnexBHeaderBytes), std::end(kAnnexBHeaderBytes));
            encodedFrame.insert(encodedFrame.end(), pParamSet, pParamSet + szParamSet);
        }
    }
    
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    if(blockBuffer == nullptr)
    {
        NSLog(@"VTCompressionOutputCallback CMSampleBufferGetDataBuffer is failed");
        return;
    }
    if (!CMBlockBufferIsRangeContiguous(blockBuffer, 0, 0))
    {
        NSLog(@"VTCompressionOutputCallback block buffer is not contiguous.");
        return;
    }
    
    size_t szBlockBuffer = CMBlockBufferGetDataLength(blockBuffer);
    
    //auto sizeHeader = encodedFrame.size();
    //encodedFrame.resize(sizeHeader + info->sizeBlockBuffer);
    uint8_t* pData = nullptr;
    status = CMBlockBufferGetDataPointer(blockBuffer, 0, nullptr, nullptr, (char **)(&pData));
    if (status != noErr)
    {
        NSLog(@"VTCompressionOutputCallback CMBlockBufferGetDataLength is failed");
        return;
    }
    
    //auto sizeEncodedFrame = encodedFrame.size();
    auto remaining = szBlockBuffer;
    while(remaining > 0)
    {
        auto nalUnitSize = *(uint32_t*)(pData);
        nalUnitSize = OSSwapBigToHostInt(nalUnitSize);
        auto nalUnitStart = pData + szNalUnitHeader;
        encodedFrame.insert(encodedFrame.end(), std::begin(kAnnexBHeaderBytes), std::end(kAnnexBHeaderBytes));
        encodedFrame.insert(encodedFrame.end(), nalUnitStart, nalUnitStart + nalUnitSize);
        
        auto sizeWritten = nalUnitSize + szNalUnitHeader;
        remaining -= sizeWritten;
        pData += sizeWritten;
    }
    if(remaining != 0)
    {
        NSLog(@"VTCompressionOutputCallback block buffer is broken");
        return;
    }
}

void VTCompressionOutputCallback(void *outputCallbackRefCon,
                                 void *sourceFrameRefCon,
                                 OSStatus status,
                                 VTEncodeInfoFlags infoFlags,
                                 CMSampleBufferRef sampleBuffer)
{
    if (status != noErr)
    {
        NSLog(@"VTCompressionOutputCallback returns failed %d", status);
        return;
    }
    if (!CMSampleBufferDataIsReady(sampleBuffer))
    {
        NSLog(@"VTCompressionOutputCallback data is not ready ");
        return;
    }
    
    VTEncoderMetal* encoder = reinterpret_cast<VTEncoderMetal*>(outputCallbackRefCon);
    std::vector<uint8>* encodedFrame = reinterpret_cast<std::vector<uint8>*>(sourceFrameRefCon);
    
    if(encoder == nullptr || encodedFrame == nullptr) {
        NSLog(@"VTCompressionOutputCallback parameter failed");
        return;
    }
    
    encoder->OnVTCompressionOutput(encodedFrame, status, infoFlags, sampleBuffer);
}

VTEncoderMetal::VTEncoderMetal(uint32_t nWidth, uint32_t nHeight, IGraphicsDevice* device)
: m_width(nWidth), m_height(nHeight), m_device(device)
{
    // Set source image buffer attributes. These attributes will be present on
    // buffers retrieved from the encoder's pixel buffer pool.
    const size_t attributes_size = 3;
    CFTypeRef keys[attributes_size] = {
        kCVPixelBufferOpenGLCompatibilityKey,
        kCVPixelBufferIOSurfacePropertiesKey,
        kCVPixelBufferPixelFormatTypeKey
    };
    CFDictionaryRef io_surface_value = CreateCFDictionary(nullptr, nullptr, 0);
    int64_t nv12type = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
    CFNumberRef pixel_format = CFNumberCreate(nullptr, kCFNumberLongType, &nv12type);
    CFTypeRef values[attributes_size] = {   kCFBooleanTrue,
        io_surface_value,
        pixel_format};
    CFDictionaryRef source_attributes = CreateCFDictionary(keys, values, attributes_size);
    
    if (io_surface_value) {
        CFRelease(io_surface_value);
        io_surface_value = nullptr;
    }
    if (pixel_format) {
        CFRelease(pixel_format);
        pixel_format = nullptr;
    }
    
    OSStatus status = VTCompressionSessionCreate(NULL, nWidth, nHeight,
                                                 kCMVideoCodecType_H264,
                                                 NULL, source_attributes, NULL,
                                                 VTCompressionOutputCallback, (__bridge void*)(this),
                                                 &encoderSession);
    if (status != noErr)
    {
        NSLog(@"VTCompressionSessionCreate failed %d", status);
    }
    
    //    NSDictionary *properties = @{
    //    (NSString *)kVTCompressionPropertyKey_RealTime: [NSNumber numberWithBool:TRUE],
    //    (NSString *)kVTCompressionPropertyKey_ProfileLevel: (NSString *)kVTProfileLevel_H264_Main_AutoLevel,
    ////    (NSString *)kVTCompressionPropertyKey_ExpectedFrameRate : [NSNumber numberWithBool:30],
    ////    (NSString *)kVTCompressionPropertyKey_AllowFrameReordering : var,
    ////    (NSString *)kVTVideoEncoderSpecification_EncoderID : @"com.apple.videotoolbox.videoencoder.h264.gva",
    ////    @"EnableHardwareAcceleratedVideoEncoder" : [NSNumber numberWithBool:TRUE],
    ////    @"RequireHardwareAcceleratedVideoEncoder" : [NSNumber numberWithBool:TRUE]
    //    };
    //
    //    status = VTSessionSetProperties(&encoderSession, (CFDictionaryRef)properties);
}

VTEncoderMetal::~VTEncoderMetal()
{
    OSStatus status = VTCompressionSessionCompleteFrames(encoderSession, kCMTimeInvalid);
    if (status != noErr)
    {
        NSLog(@"VTCompressionSessionCompleteFrames failed %d", status);
    }
}

bool H264CMSampleBufferToAnnexBBuffer(
                                      CMSampleBufferRef sampleBuffer,
                                      bool isKeyframe,
                                      rtc::Buffer* pAnnexBBuffer,
                                      webrtc::RTPFragmentationHeader** ppHeader) {
    RTC_DCHECK(sampleBuffer);
    RTC_DCHECK(ppHeader);
    *ppHeader = nullptr;
    
    // Get format description from the sample buffer.
    CMVideoFormatDescriptionRef description =
    CMSampleBufferGetFormatDescription(sampleBuffer);
    if (description == nullptr) {
        NSLog(@"Failed to get sample buffer's description.");
        return false;
    }
    
    // Get parameter set information.
    int nalu_header_size = 0;
    size_t param_set_count = 0;
    OSStatus status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                                                                         description, 0, nullptr, nullptr, &param_set_count, &nalu_header_size);
    if (status != noErr) {
        NSLog(@"Failed to get parameter set.");
        return false;
    }
    RTC_CHECK_EQ(nalu_header_size, kAvccHeaderByteSize);
    RTC_DCHECK_EQ(param_set_count, 2u);
    
    // Truncate any previous data in the buffer without changing its capacity.
    pAnnexBBuffer->SetSize(0);
    
    size_t nalu_offset = 0;
    std::vector<size_t> frag_offsets;
    std::vector<size_t> frag_lengths;
    
    // Place all parameter sets at the front of buffer.
    if (isKeyframe) {
        size_t param_set_size = 0;
        const uint8_t* param_set = nullptr;
        for (size_t i = 0; i < param_set_count; ++i) {
            status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                                                                        description, i, &param_set, &param_set_size, nullptr, nullptr);
            if (status != noErr) {
                NSLog(@"Failed to get parameter set.");
                return false;
            }
            // Update buffer.
            pAnnexBBuffer->AppendData(kAnnexBHeaderBytes, sizeof(kAnnexBHeaderBytes));
            pAnnexBBuffer->AppendData(reinterpret_cast<const char*>(param_set),
                                      param_set_size);
            // Update fragmentation.
            frag_offsets.push_back(nalu_offset + sizeof(kAnnexBHeaderBytes));
            frag_lengths.push_back(param_set_size);
            nalu_offset += sizeof(kAnnexBHeaderBytes) + param_set_size;
        }
    }
    
    // Get block buffer from the sample buffer.
    CMBlockBufferRef block_buffer =
    CMSampleBufferGetDataBuffer(sampleBuffer);
    if (block_buffer == nullptr) {
        NSLog(@"Failed to get sample buffer's block buffer.");
        return false;
    }
    CMBlockBufferRef contiguous_buffer = nullptr;
    // Make sure block buffer is contiguous.
    if (!CMBlockBufferIsRangeContiguous(block_buffer, 0, 0)) {
        status = CMBlockBufferCreateContiguous(
                                               nullptr, block_buffer, nullptr, nullptr, 0, 0, 0, &contiguous_buffer);
        if (status != noErr) {
            NSLog(@"Failed to flatten non-contiguous block buffer: %d", status);
            return false;
        }
    } else {
        contiguous_buffer = block_buffer;
        // Retain to make cleanup easier.
        CFRetain(contiguous_buffer);
        block_buffer = nullptr;
    }
    
    // Now copy the actual data.
    char* data_ptr = nullptr;
    size_t block_buffer_size = CMBlockBufferGetDataLength(contiguous_buffer);
    status = CMBlockBufferGetDataPointer(contiguous_buffer, 0, nullptr, nullptr,
                                         &data_ptr);
    if (status != noErr) {
        NSLog(@"Failed to get block buffer data.");
        CFRelease(contiguous_buffer);
        return false;
    }
    size_t bytes_remaining = block_buffer_size;
    while (bytes_remaining > 0) {
        // The size type here must match |nalu_header_size|, we expect 4 bytes.
        // Read the length of the next packet of data. Must convert from big endian
        // to host endian.
        RTC_DCHECK_GE(bytes_remaining, (size_t)nalu_header_size);
        uint32_t* uint32_data_ptr = reinterpret_cast<uint32_t*>(data_ptr);
        uint32_t packet_size = CFSwapInt32BigToHost(*uint32_data_ptr);
        // Update buffer.
        pAnnexBBuffer->AppendData(kAnnexBHeaderBytes, sizeof(kAnnexBHeaderBytes));
        pAnnexBBuffer->AppendData(data_ptr + nalu_header_size, packet_size);
        // Update fragmentation.
        frag_offsets.push_back(nalu_offset + sizeof(kAnnexBHeaderBytes));
        frag_lengths.push_back(packet_size);
        nalu_offset += sizeof(kAnnexBHeaderBytes) + packet_size;
        
        size_t bytes_written = packet_size + sizeof(kAnnexBHeaderBytes);
        bytes_remaining -= bytes_written;
        data_ptr += bytes_written;
    }
    RTC_DCHECK_EQ(bytes_remaining, (size_t)0);
    
    std::unique_ptr<webrtc::RTPFragmentationHeader> header;
    header.reset(new webrtc::RTPFragmentationHeader());
    header->VerifyAndAllocateFragmentationHeader(frag_offsets.size());
    RTC_DCHECK_EQ(frag_lengths.size(), frag_offsets.size());
    for (size_t i = 0; i < frag_offsets.size(); ++i) {
        header->fragmentationOffset[i] = frag_offsets[i];
        header->fragmentationLength[i] = frag_lengths[i];
        header->fragmentationPlType[i] = 0;
        header->fragmentationTimeDiff[i] = 0;
    }
    *ppHeader = header.release();
    CFRelease(contiguous_buffer);
    return true;
}



void VTEncoderMetal::OnVTCompressionOutput(std::vector<uint8>* workBuffer, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer) {
    
    bool isKeyframe = false;
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, 0);
    if (attachments != nullptr && CFArrayGetCount(attachments)) {
        CFDictionaryRef attachment = static_cast<CFDictionaryRef>(CFArrayGetValueAtIndex(attachments, 0));
        isKeyframe = !CFDictionaryContainsKey(attachment, kCMSampleAttachmentKey_NotSync);
    }
    
    if (isKeyframe) {
        NSLog(@"Generated keyframe");
    }
    
    // Convert the sample buffer into a buffer suitable for RTP packetization.
    // TODO(tkchin): Allocate buffers through a pool.
    std::unique_ptr<rtc::Buffer> buffer(new rtc::Buffer());
    std::unique_ptr<webrtc::RTPFragmentationHeader> header;
    {
        webrtc::RTPFragmentationHeader* pHeader;
        bool result = H264CMSampleBufferToAnnexBBuffer(sampleBuffer, isKeyframe,
                                                       buffer.get(), &pHeader);
        header.reset(pHeader);
        if (!result) {
            return;
        }
    }
    
    CMTime timeStamp = CMTimeMake(rtc::TimeMillis(), 1000);
    
    webrtc::EncodedImage frame(buffer->data(), buffer->size(), buffer->size());
    frame._encodedWidth = m_width;
    frame._encodedHeight = m_height;
    frame._completeFrame = true;
    frame._frameType =
    isKeyframe ? webrtc::kVideoFrameKey : webrtc::kVideoFrameDelta;
    frame.capture_time_ms_ = rtc::TimeMillis();
    frame.SetTimestamp(timeStamp.value/timeStamp.timescale);
    frame.rotation_ = webrtc::kVideoRotation_0;
    
        
    //    PrepareEncodedFrame(sampleBuffer, *workBuffer);
    //
    rtc::scoped_refptr<VTFrameBuffer> vtBuffer = new rtc::RefCountedObject<VTFrameBuffer>(m_width, m_height, *workBuffer);
    int64 timestamp = rtc::TimeMillis();
    webrtc::VideoFrame videoFrame{buffer, webrtc::VideoRotation::kVideoRotation_0, timestamp};
    videoFrame.set_ntp_time_ms(timestamp);
    CaptureFrame(frame);
}

void VTEncoderMetal::InitV()
{
    for(NSInteger i = 0; i < bufferedFrameNum; i++)
    {
        CVPixelBufferPoolRef pixelBufferPool; // Pool to precisely match the format
        pixelBufferPool = VTCompressionSessionGetPixelBufferPool(encoderSession);
        
        CVReturn result = CVPixelBufferPoolCreatePixelBuffer(NULL, pixelBufferPool, &m_pixelBuffers[i]);
        if(result != kCVReturnSuccess)
        {
            throw;
        }
        id<MTLDevice> device_ = (__bridge id<MTLDevice>)m_device->GetEncodeDevicePtrV();
        
        
        CVMetalTextureCacheRef textureCache;
        result = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device_, nil, &textureCache);
        if(result != kCVReturnSuccess)
        {
            throw;
        }
        
        CVMetalTextureRef imageTexture;
        result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           textureCache,
                                                           m_pixelBuffers[i],
                                                           nil,
                                                           MTLPixelFormatBGRA8Unorm_sRGB,
                                                           m_width, m_height, 0,
                                                           &imageTexture);
        if(result != kCVReturnSuccess)
        {
            throw;
        }
        
        auto metalDevice = reinterpret_cast<MetalGraphicsDevice*>(m_device);
        
        id<MTLTexture> tex = CVMetalTextureGetTexture(imageTexture);
        m_renderTextures[i] = metalDevice->CreateDefaultTextureFromNativeV(m_width, m_height, tex);
    }
}

void VTEncoderMetal::SetRate(uint32_t rate)
{
}

void VTEncoderMetal::UpdateSettings()
{
}

bool VTEncoderMetal::CopyBuffer(void* srcNativeTexture)
{
    const int curFrameNum = GetCurrentFrameCount() % bufferedFrameNum;
    const auto tex = m_renderTextures[curFrameNum];
    if (tex == nullptr)
        return false;
    m_device->CopyResourceFromNativeV(tex, srcNativeTexture);
    return true;
}

bool VTEncoderMetal::EncodeFrame()
{
    UpdateSettings();
    uint32 bufferIndexToWrite = frameCount % bufferedFrameNum;
    
    CMTime presentationTimeStamp = CMTimeMake(frameCount, 1000);
    VTEncodeInfoFlags flags;
    OSStatus status = VTCompressionSessionEncodeFrame(encoderSession,
                                                      m_pixelBuffers[bufferIndexToWrite],
                                                      presentationTimeStamp,
                                                      kCMTimeInvalid,
                                                      NULL, (void*)&m_workBuffers[bufferIndexToWrite], &flags);
    
    if (status != noErr)
    {
        return false;
    }
    frameCount++;
    return true;
}
bool VTEncoderMetal::IsSupported() const
{
    return true;
}
void VTEncoderMetal::SetIdrFrame()
{
    // Nothing to do
}
}
