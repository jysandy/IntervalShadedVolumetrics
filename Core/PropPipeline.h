#pragma once

#include "pch.h"

#include "Gradient/RootSignature.h"
#include "Gradient/PipelineState.h"
#include <directxtk12/VertexTypes.h>

namespace ISV
{
    class PropPipeline
    {
    public:

        struct DirectionalLight
        {
            DirectX::XMFLOAT3 Color;
            float Strength;
            DirectX::XMFLOAT3 Direction;
            float Pad;
        };

        struct __declspec(align(16)) Constants
        {
            DirectX::XMMATRIX World;
            DirectX::XMMATRIX WorldViewProj;
            DirectionalLight Light;
            DirectX::XMFLOAT3 CameraPosition;
            float Pad;
        };

        using VertexType = DirectX::VertexPositionNormalTexture;

        explicit PropPipeline(ID3D12Device2* device);
        virtual ~PropPipeline() noexcept = default;

        void Apply(ID3D12GraphicsCommandList* cl,
            bool multisampled = true);

        Gradient::GraphicsMemoryManager::DescriptorView ShadowMap;
        DirectX::SimpleMath::Matrix World;
        DirectX::SimpleMath::Matrix View;
        DirectX::SimpleMath::Matrix Proj;
        DirectX::SimpleMath::Matrix ShadowTransform;
        DirectX::SimpleMath::Vector3 CameraPosition;
        DirectionalLight Light;

    private:
        void InitializeRootSignature(ID3D12Device* device);
        //void InitializeShadowPSO(ID3D12Device2* device);
        void InitializeRenderPSO(ID3D12Device2* device);

        Gradient::RootSignature m_rootSignature;
        std::unique_ptr<Gradient::PipelineState> m_renderPipelineState;
        std::unique_ptr<Gradient::PipelineState> m_shadowPipelineState;


    };
}