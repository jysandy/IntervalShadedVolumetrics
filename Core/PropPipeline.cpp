#include "pch.h"

#include "Core/PropPipeline.h"
#include "Gradient/ReadData.h"

namespace ISV
{
    PropPipeline::PropPipeline(ID3D12Device2* device)
    {
        InitializeRootSignature(device);
        InitializeShadowPSO(device);
        InitializeRenderPSO(device);
    }

    void PropPipeline::InitializeRootSignature(ID3D12Device* device)
    {
        m_rootSignature.AddCBV(0, 0); // constants
        m_rootSignature.AddSRV(0, 0); // shadow map
        m_rootSignature.AddSRV(1, 0); // volumetric shadow map

        m_rootSignature.AddStaticSampler(CD3DX12_STATIC_SAMPLER_DESC(0,
            D3D12_FILTER_MIN_MAG_MIP_LINEAR,
            D3D12_TEXTURE_ADDRESS_MODE_CLAMP,
            D3D12_TEXTURE_ADDRESS_MODE_CLAMP,
            D3D12_TEXTURE_ADDRESS_MODE_CLAMP),
            0, 0);

        m_rootSignature.AddStaticSampler(CD3DX12_STATIC_SAMPLER_DESC(1,
            D3D12_FILTER_COMPARISON_MIN_MAG_LINEAR_MIP_POINT,
            D3D12_TEXTURE_ADDRESS_MODE_BORDER,
            D3D12_TEXTURE_ADDRESS_MODE_BORDER,
            D3D12_TEXTURE_ADDRESS_MODE_BORDER,
            0,
            1,
            D3D12_COMPARISON_FUNC_LESS_EQUAL),
            1,
            0);

        m_rootSignature.Build(device);
    }

    void PropPipeline::InitializeRenderPSO(ID3D12Device2* device)
    {
        D3D12_GRAPHICS_PIPELINE_STATE_DESC psoDesc 
            = Gradient::PipelineState::GetDefaultDesc();

        auto vsData = DX::ReadData(L"Prop_VS.cso");
        auto psData = DX::ReadData(L"Prop_PS.cso");

        psoDesc.pRootSignature = m_rootSignature.Get();
        psoDesc.InputLayout = VertexType::InputLayout;
        psoDesc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
        psoDesc.VS = { vsData.data(), vsData.size() };
        psoDesc.PS = { psData.data(), psData.size() };

        m_renderPipelineState = std::make_unique<Gradient::PipelineState>(psoDesc);
        m_renderPipelineState->Build(device);
    }

    void PropPipeline::InitializeShadowPSO(ID3D12Device2* device)
    {
        D3D12_GRAPHICS_PIPELINE_STATE_DESC psoDesc
            = Gradient::PipelineState::GetDefaultShadowDesc();

        auto vsData = DX::ReadData(L"Prop_VS.cso");

        psoDesc.pRootSignature = m_rootSignature.Get();
        psoDesc.InputLayout = VertexType::InputLayout;
        psoDesc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
        psoDesc.VS = { vsData.data(), vsData.size() };

        m_shadowPipelineState = std::make_unique<Gradient::PipelineState>(psoDesc);
        m_shadowPipelineState->Build(device);
    }

    void PropPipeline::Apply(ID3D12GraphicsCommandList* cl, bool multisampled)
    {
        m_rootSignature.SetOnCommandList(cl);
        m_renderPipelineState->Set(cl, multisampled);

        Constants constants;
        constants.World = World.Transpose();
        constants.WorldViewProj = (World * View * Proj).Transpose();
        constants.CameraPosition = CameraPosition;
        constants.Light = Light;
        constants.ShadowTransform = ShadowTransform.Transpose();
        constants.VolumetricShadowTransform = VolumetricShadowTransform.Transpose();
        constants.RenderingMethod = RenderingMethod;

        m_rootSignature.SetCBV(cl, 0, 0, constants); 
        m_rootSignature.SetSRV(cl, 0, 0, ShadowMap);
        m_rootSignature.SetSRV(cl, 1, 0, VolumetricShadowMap);


        cl->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    }

    void PropPipeline::ApplyShadows(ID3D12GraphicsCommandList* cl)
    {
        m_rootSignature.SetOnCommandList(cl);
        m_shadowPipelineState->Set(cl, false);

        Constants constants;
        constants.World = World.Transpose();
        constants.WorldViewProj = (World * View * Proj).Transpose();
        constants.CameraPosition = CameraPosition;
        constants.Light = Light;
        constants.RenderingMethod = RenderingMethod;

        m_rootSignature.SetCBV(cl, 0, 0, constants);


        cl->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    }
}