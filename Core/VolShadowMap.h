#pragma once

#include "pch.h"
#include "Gradient/BarrierResource.h"
#include "Gradient/GraphicsMemoryManager.h"
#include <directxtk12/SimpleMath.h>
#include <array>

namespace ISV
{
    class VolShadowMap
    {
    public:
        const uint32_t Width = 256;
        const uint32_t Depth = 5;

        using DrawFn = std::function<void(DirectX::SimpleMath::Matrix,
            DirectX::SimpleMath::Matrix, DirectX::BoundingOrientedBox, float)>;

        VolShadowMap(ID3D12Device* device,
            float sceneRadius,
            DirectX::SimpleMath::Vector3 sceneCentre = DirectX::SimpleMath::Vector3::Zero);

        void SetLightDirection(const DirectX::SimpleMath::Vector3& direction);
        void Render(ID3D12GraphicsCommandList* cl, DrawFn fn);

        Gradient::GraphicsMemoryManager::DescriptorView 
            TransitionAndGetSRV(ID3D12GraphicsCommandList* cl);
        DirectX::SimpleMath::Matrix GetShadowTransform() const;

    private:
        D3D12_VIEWPORT m_shadowMapViewport;
        Gradient::GraphicsMemoryManager::DescriptorView m_srv;
        Gradient::BarrierResource m_texture3D;
        Gradient::BarrierResource m_texture2D;
        Gradient::GraphicsMemoryManager::DescriptorView m_rtv;

        DirectX::BoundingOrientedBox GetBoundingBox(uint32_t depthSlice);


        DirectX::SimpleMath::Vector3 m_sceneCentre;
        float m_sceneRadius;

        DirectX::SimpleMath::Matrix m_shadowMapView;
        DirectX::SimpleMath::Matrix m_shadowMapViewInverse;
        DirectX::SimpleMath::Matrix m_shadowMapProj;

        DirectX::BoundingOrientedBox m_shadowBB;
        DirectX::SimpleMath::Vector3 m_lightPosition;
    };
}