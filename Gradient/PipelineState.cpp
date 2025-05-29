#include "pch.h"
#include "Gradient/PipelineState.h"

#include <directxtk12/VertexTypes.h>
#include <directxtk12/CommonStates.h>

namespace Gradient
{
    PipelineState::PipelineState(D3D12_GRAPHICS_PIPELINE_STATE_DESC psoDesc)
        : m_desc(psoDesc)
    {
    }

    PipelineState::PipelineState(D3DX12_MESH_SHADER_PIPELINE_STATE_DESC psoDesc)
        : m_meshDesc(psoDesc), m_useMeshShader(true)
    {
    }


    void PipelineState::Build(ID3D12Device2* device)
    {
        assert(!m_isBuilt);

        if (m_useMeshShader)
        {
            auto psoStream = CD3DX12_PIPELINE_MESH_STATE_STREAM(m_meshDesc);

            D3D12_PIPELINE_STATE_STREAM_DESC streamDesc;
            streamDesc.SizeInBytes = sizeof(psoStream);
            streamDesc.pPipelineStateSubobjectStream = &psoStream;

            DX::ThrowIfFailed(
                device->CreatePipelineState(&streamDesc,
                    IID_PPV_ARGS(&m_singleSampledPSO)));

            auto multisampledPSODesc = m_meshDesc;

            multisampledPSODesc.RasterizerState.MultisampleEnable = TRUE;
            multisampledPSODesc.SampleDesc.Count = 4;
            multisampledPSODesc.SampleDesc.Quality = 0;

            psoStream = CD3DX12_PIPELINE_MESH_STATE_STREAM(m_meshDesc);
            streamDesc.SizeInBytes = sizeof(psoStream);
            streamDesc.pPipelineStateSubobjectStream = &psoStream;

            DX::ThrowIfFailed(
                device->CreatePipelineState(&streamDesc,
                    IID_PPV_ARGS(&m_multisampledPSO)));
        }
        else
        {
            DX::ThrowIfFailed(
                device->CreateGraphicsPipelineState(&m_desc,
                    IID_PPV_ARGS(&m_singleSampledPSO)));

            auto multisampledPSODesc = m_desc;

            multisampledPSODesc.RasterizerState.MultisampleEnable = TRUE;
            multisampledPSODesc.SampleDesc.Count = 4;
            multisampledPSODesc.SampleDesc.Quality = 0;

            DX::ThrowIfFailed(
                device->CreateGraphicsPipelineState(&multisampledPSODesc,
                    IID_PPV_ARGS(&m_multisampledPSO)));
        }

        m_isBuilt = true;
    }

    D3D12_GRAPHICS_PIPELINE_STATE_DESC PipelineState::GetDefaultDesc()
    {
        D3D12_GRAPHICS_PIPELINE_STATE_DESC psoDesc = {};

        psoDesc.InputLayout = DirectX::VertexPositionNormalTexture::InputLayout;
        psoDesc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
        psoDesc.BlendState = CD3DX12_BLEND_DESC(D3D12_DEFAULT);
        psoDesc.DepthStencilState = DirectX::CommonStates::DepthDefault;
        psoDesc.SampleMask = UINT_MAX;
        psoDesc.RasterizerState = DirectX::CommonStates::CullCounterClockwise;
        psoDesc.NumRenderTargets = 1;
        psoDesc.DSVFormat = DXGI_FORMAT_D32_FLOAT;
        psoDesc.RTVFormats[0] = DXGI_FORMAT_R16G16B16A16_FLOAT;
        psoDesc.SampleDesc.Count = 1;
        psoDesc.SampleDesc.Quality = 0;

        return psoDesc;
    }

    D3DX12_MESH_SHADER_PIPELINE_STATE_DESC PipelineState::GetDefaultMeshDesc()
    {
        D3DX12_MESH_SHADER_PIPELINE_STATE_DESC psoDesc = {};

        psoDesc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
        psoDesc.BlendState = CD3DX12_BLEND_DESC(D3D12_DEFAULT);
        psoDesc.DepthStencilState = DirectX::CommonStates::DepthDefault;
        psoDesc.SampleMask = UINT_MAX;
        psoDesc.RasterizerState = DirectX::CommonStates::CullCounterClockwise;
        psoDesc.NumRenderTargets = 1;
        psoDesc.DSVFormat = DXGI_FORMAT_D32_FLOAT;
        psoDesc.RTVFormats[0] = DXGI_FORMAT_R16G16B16A16_FLOAT;
        psoDesc.SampleDesc.Count = 1;
        psoDesc.SampleDesc.Quality = 0;

        return psoDesc;
    }

    D3D12_GRAPHICS_PIPELINE_STATE_DESC PipelineState::GetDefaultShadowDesc()
    {
        D3D12_GRAPHICS_PIPELINE_STATE_DESC psoDesc = PipelineState::GetDefaultDesc();

        auto rsDesc = CD3DX12_RASTERIZER_DESC1();
        rsDesc.FillMode = D3D12_FILL_MODE_SOLID;
        rsDesc.CullMode = D3D12_CULL_MODE_BACK;
        rsDesc.FrontCounterClockwise = FALSE;
        rsDesc.DepthClipEnable = TRUE;
        rsDesc.MultisampleEnable = FALSE;
        rsDesc.AntialiasedLineEnable = FALSE;
        rsDesc.DepthBias = 10000;
        rsDesc.SlopeScaledDepthBias = 1.f;
        rsDesc.DepthBiasClamp = 0.f;

        psoDesc.RasterizerState = rsDesc;
        psoDesc.NumRenderTargets = 0;
        for (int i = 0; i < 8; i++)
            psoDesc.RTVFormats[i] = DXGI_FORMAT_UNKNOWN;

        return psoDesc;
    }

    D3DX12_MESH_SHADER_PIPELINE_STATE_DESC PipelineState::GetDefaultShadowMeshDesc()
    {
        D3DX12_MESH_SHADER_PIPELINE_STATE_DESC psoDesc = PipelineState::GetDefaultMeshDesc();

        auto rsDesc = CD3DX12_RASTERIZER_DESC1();
        rsDesc.FillMode = D3D12_FILL_MODE_SOLID;
        rsDesc.CullMode = D3D12_CULL_MODE_BACK;
        rsDesc.FrontCounterClockwise = FALSE;
        rsDesc.DepthClipEnable = TRUE;
        rsDesc.MultisampleEnable = FALSE;
        rsDesc.AntialiasedLineEnable = FALSE;
        rsDesc.DepthBias = 10000;
        rsDesc.SlopeScaledDepthBias = 1.f;
        rsDesc.DepthBiasClamp = 0.f;

        psoDesc.RasterizerState = rsDesc;
        psoDesc.NumRenderTargets = 0;
        for (int i = 0; i < 8; i++)
            psoDesc.RTVFormats[i] = DXGI_FORMAT_UNKNOWN;

        return psoDesc;
    }

    D3D12_GRAPHICS_PIPELINE_STATE_DESC PipelineState::GetDepthWriteDisableDesc()
    {
        D3D12_GRAPHICS_PIPELINE_STATE_DESC psoDesc = PipelineState::GetDefaultDesc();

        psoDesc.DepthStencilState = DirectX::CommonStates::DepthRead;

        return psoDesc;
    }

    D3DX12_MESH_SHADER_PIPELINE_STATE_DESC PipelineState::GetDepthWriteDisableMeshDesc()
    {
        D3DX12_MESH_SHADER_PIPELINE_STATE_DESC psoDesc = PipelineState::GetDefaultMeshDesc();

        psoDesc.DepthStencilState = DirectX::CommonStates::DepthRead;

        return psoDesc;
    }

    D3D12_GRAPHICS_PIPELINE_STATE_DESC PipelineState::GetDesc()
    {
        return m_desc;
    }

    D3DX12_MESH_SHADER_PIPELINE_STATE_DESC PipelineState::GetMeshDesc()
    {
        return m_meshDesc;
    }

    void PipelineState::Set(ID3D12GraphicsCommandList* cl,
        bool multisampled)
    {
        assert(m_isBuilt);

        if (multisampled)
            cl->SetPipelineState(m_multisampledPSO.Get());
        else
            cl->SetPipelineState(m_singleSampledPSO.Get());
    }
}