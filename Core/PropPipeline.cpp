#include "pch.h"

#include "Core/PropPipeline.h"
#include "Gradient/ReadData.h"

namespace ISV
{
    PropPipeline::PropPipeline(ID3D12Device2* device)
    {
        InitializeRootSignature(device);
        //InitializeShadowPSO(device);
        InitializeRenderPSO(device);
    }

    void PropPipeline::InitializeRootSignature(ID3D12Device* device)
    {
        m_rootSignature.AddCBV(0, 0);
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

    void PropPipeline::Apply(ID3D12GraphicsCommandList* cl, bool multisampled)
    {
        m_rootSignature.SetOnCommandList(cl);
        m_renderPipelineState->Set(cl, multisampled);

        Constants constants;
        constants.World = World.Transpose();
        constants.WorldViewProj = (World * View * Proj).Transpose();
        constants.CameraPosition = CameraPosition;
        constants.Light = Light;

        m_rootSignature.SetCBV(cl, 0, 0, constants);


        cl->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    }
}