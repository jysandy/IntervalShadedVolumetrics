#include "pch.h"

#include "Gradient/Rendering/TextureDrawer.h"
#include <directxtk12/ResourceUploadBatch.h>
#include <directxtk12/CommonStates.h>
#include "Gradient/ReadData.h"

namespace Gradient::Rendering
{
    Gradient::RootSignature TextureDrawer::s_rootSignature;

    void TextureDrawer::CreateRootSignature(ID3D12Device* device)
    {
        s_rootSignature.AddSRV(0, 0);
        s_rootSignature.AddCBV(0, 0);
        s_rootSignature.AddCBV(0, 1); // our usable CBV
        s_rootSignature.AddSRV(0, 1); // our usable SRV

        s_rootSignature.AddStaticSampler(
            CD3DX12_STATIC_SAMPLER_DESC(0, D3D12_FILTER_MIN_MAG_MIP_LINEAR,
                D3D12_TEXTURE_ADDRESS_MODE_CLAMP,
                D3D12_TEXTURE_ADDRESS_MODE_CLAMP,
                D3D12_TEXTURE_ADDRESS_MODE_CLAMP),
            0, 0);

        s_rootSignature.Build(device);
    }

    void TextureDrawer::Shutdown()
    {
        s_rootSignature.Reset();
    }

    void TextureDrawer::SetSRV(ID3D12GraphicsCommandList* cl,
        GraphicsMemoryManager::DescriptorView index)
    {
        s_rootSignature.SetSRV(cl, 0, 1, index);
    }

    TextureDrawer::TextureDrawer(ID3D12Device* device,
        ID3D12CommandQueue* cq,
        DXGI_FORMAT format,
        std::wstring shaderPath)
    {
        assert(s_rootSignature.Get() != nullptr);

        auto psData = DX::ReadData(shaderPath.c_str());

        DirectX::ResourceUploadBatch resourceUpload(device);

        resourceUpload.Begin();

        DirectX::RenderTargetState rtState(
            format,
            DXGI_FORMAT_D32_FLOAT);

        DirectX::SpriteBatchPipelineStateDescription pd(rtState);
        pd.customPixelShader = { psData.data(), psData.size() };
        pd.customRootSignature = s_rootSignature.Get();

        m_spriteBatch = std::make_unique<DirectX::SpriteBatch>(
            device,
            resourceUpload,
            pd);

        // Upload the resources to the GPU.
        auto uploadResourcesFinished
            = resourceUpload.End(cq);

        // Wait for the upload thread to terminate
        uploadResourcesFinished.wait();
    }

    TextureDrawer::TextureDrawer(ID3D12Device* device,
        ID3D12CommandQueue* cq,
        DXGI_FORMAT format)
    {
        DirectX::ResourceUploadBatch resourceUpload(device);

        resourceUpload.Begin();

        DirectX::RenderTargetState rtState(
            format,
            DXGI_FORMAT_D32_FLOAT);

        DirectX::SpriteBatchPipelineStateDescription pd(rtState);

        m_spriteBatch = std::make_unique<DirectX::SpriteBatch>(
            device,
            resourceUpload,
            pd);

        // Upload the resources to the GPU.
        auto uploadResourcesFinished
            = resourceUpload.End(cq);

        // Wait for the upload thread to terminate
        uploadResourcesFinished.wait();
    }

    void TextureDrawer::Draw(ID3D12GraphicsCommandList* cl,
        GraphicsMemoryManager::DescriptorView texSRV,
        D3D12_VIEWPORT viewport,
        RECT inputSize,
        RECT outputSize)
    {
        auto gmm = GraphicsMemoryManager::Get();

        m_spriteBatch->SetViewport(viewport);
        m_spriteBatch->Begin(cl);

        m_spriteBatch->Draw(texSRV->GetGPUHandle(),
            {
                static_cast<uint32_t>(inputSize.right),
                static_cast<uint32_t>(inputSize.bottom)
            },
            outputSize);

        m_spriteBatch->End();
    }
}