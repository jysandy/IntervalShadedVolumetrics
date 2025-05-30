#pragma once
#include "pch.h"
#include "Gradient/BarrierResource.h"
#include "Gradient/GraphicsMemoryManager.h"
#include "Gradient/Rendering/TextureDrawer.h"
#include <directxtk12/CommonStates.h>
#include <directxtk12/SpriteBatch.h>
#include <memory>

namespace Gradient::Rendering
{
    class RenderTexture
    {
    public:
        RenderTexture(
            ID3D12Device* device,
            UINT width,
            UINT height,
            DXGI_FORMAT format,
            bool multisamplingEnabled);

        ID3D12Resource* GetTexture();
        BarrierResource* GetBarrierResource();
        GraphicsMemoryManager::DescriptorView GetRTV();
        ID3D12Resource* GetSingleSampledTexture();
        BarrierResource* GetSingleSampledBarrierResource();
        BarrierResource* GetDepthBuffer();
        GraphicsMemoryManager::DescriptorView GetSRV();
        RECT GetOutputSize();
        DXGI_FORMAT GetDepthBufferFormat() const;
        DXGI_FORMAT GetRenderTargetFormat() const;
        UINT GetSampleCount() const;
        void CopyToSingleSampled(ID3D12GraphicsCommandList* cl);
        void ClearAndSetAsTarget(ID3D12GraphicsCommandList* cl);
        void Clear(ID3D12GraphicsCommandList* cl);
        void SetDepthOnly(ID3D12GraphicsCommandList* cl);
        void SetDepthAndRT(ID3D12GraphicsCommandList* cl);
        void DrawTo(ID3D12GraphicsCommandList* cl,
            RenderTexture* destination,
            TextureDrawer* texDrawer,
            D3D12_VIEWPORT viewport);

    private:
        bool m_multisamplingEnabled;
        DXGI_FORMAT m_format;
        RECT m_size;

        BarrierResource m_offscreenRT;
        BarrierResource m_singleSampledRT;
        GraphicsMemoryManager::DescriptorView m_rtv;
        GraphicsMemoryManager::DescriptorView m_srv;

        BarrierResource m_depthBuffer;
        GraphicsMemoryManager::DescriptorView m_dsv;
    };
}