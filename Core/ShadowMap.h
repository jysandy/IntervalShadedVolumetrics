#pragma once

#include "pch.h"

#include <directxtk12/SimpleMath.h>
#include "Gradient/GraphicsMemoryManager.h"
#include "Gradient/BarrierResource.h"

namespace ISV
{
    class ShadowMap
    {
    public:
        ShadowMap(ID3D12Device* device,
            DirectX::SimpleMath::Vector3 lightDirection,
            float sceneRadius,
            DirectX::SimpleMath::Vector3 sceneCentre = DirectX::SimpleMath::Vector3::Zero);

        DirectX::SimpleMath::Matrix GetShadowTransform() const;

        void SetLightDirection(const DirectX::SimpleMath::Vector3& direction);

        void ClearAndSetDSV(ID3D12GraphicsCommandList* cl);
        void TransitionToShaderResource(ID3D12GraphicsCommandList* cl);

        DirectX::SimpleMath::Vector3 GetDirection() const;
        DirectX::SimpleMath::Vector3 GetPosition() const;

        DirectX::SimpleMath::Matrix GetView() const;
        DirectX::SimpleMath::Matrix GetProjection() const;

        Gradient::GraphicsMemoryManager::DescriptorView GetShadowMapSRV() const;

    private:
        D3D12_VIEWPORT m_shadowMapViewport;
        Gradient::GraphicsMemoryManager::DescriptorView m_shadowMapSRV;
        Gradient::BarrierResource m_shadowMapDS;
        Gradient::GraphicsMemoryManager::DescriptorView m_shadowMapDSV;

        DirectX::SimpleMath::Vector3 m_sceneCentre;
        float m_sceneRadius;
        float m_width;
        DirectX::SimpleMath::Vector3 m_lightDirection;
        DirectX::SimpleMath::Matrix m_shadowMapView;
        DirectX::SimpleMath::Matrix m_shadowMapViewInverse;
        DirectX::SimpleMath::Matrix m_shadowMapProj;

        DirectX::SimpleMath::Vector3 m_lightPosition; // the effective position that the shadow is cast from

    };
}