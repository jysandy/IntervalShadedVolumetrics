#include "pch.h"

#include "Core/VolShadowMap.h"

using namespace DirectX::SimpleMath;

namespace ISV
{
    VolShadowMap::VolShadowMap(ID3D12Device* device,
        float sceneRadius,
        DirectX::SimpleMath::Vector3 sceneCentre)
    {
        auto gmm = Gradient::GraphicsMemoryManager::Get();

        m_sceneRadius = sceneRadius;
        m_sceneCentre = sceneCentre;

        m_shadowMapProj = Matrix::CreateOrthographicOffCenter(
            -sceneRadius,
            sceneRadius,
            -sceneRadius,
            sceneRadius,
            0.0,
            2 * sceneRadius
        );

        m_shadowMapViewport =
        {
            0,
            0,
            (float)Width,
            (float)Width,
            0,
            1.f
        };

        auto format = DXGI_FORMAT_R32_FLOAT;

        auto textureDesc = CD3DX12_RESOURCE_DESC::Tex3D(
            format,
            Width,
            Width,
            Depth,
            1,
            D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET
        );

        D3D12_CLEAR_VALUE clearValue = {};
        clearValue.Format = format;
        clearValue.Color[0] = 0;
        clearValue.Color[1] = 0;
        clearValue.Color[2] = 0;
        clearValue.Color[3] = 0;

        m_texture3D.Create(device,
            &textureDesc,
            D3D12_RESOURCE_STATE_RENDER_TARGET,
            &clearValue);

        m_texture3D.Get()->SetName(L"Volumetric Shadow Map");

        auto textureDesc2D = CD3DX12_RESOURCE_DESC::Tex2D(
            format,
            Width,
            Width,
            1,
            1
        );

        textureDesc2D.Flags |= D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;

        m_texture2D.Create(device,
            &textureDesc2D,
            D3D12_RESOURCE_STATE_RENDER_TARGET,
            &clearValue);

        auto rtvDesc = D3D12_RENDER_TARGET_VIEW_DESC();
        rtvDesc.Format = format;
        rtvDesc.ViewDimension = D3D12_RTV_DIMENSION_TEXTURE2D;
        m_rtv = gmm->CreateRTV(device, rtvDesc, m_texture2D.Get());

        auto srvDesc = D3D12_SHADER_RESOURCE_VIEW_DESC();
        srvDesc.Format = format;
        srvDesc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE3D;
        srvDesc.Texture3D.MipLevels = 1;
        srvDesc.Texture3D.MostDetailedMip = 0;
        srvDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;

        m_srv = gmm->CreateSRV(device,
            m_texture3D.Get(),
            &srvDesc);
    }

    void VolShadowMap::SetLightDirection(const DirectX::SimpleMath::Vector3& direction)
    {
        auto lightDirection = direction;
        lightDirection.Normalize();

        m_lightPosition = m_sceneCentre - m_sceneRadius * lightDirection;

        m_shadowMapView = Matrix::CreateLookAt(m_lightPosition,
            m_sceneCentre,
            Vector3::UnitY);
        m_shadowMapViewInverse = m_shadowMapView.Invert();
    }

    DirectX::BoundingOrientedBox VolShadowMap::GetBoundingBox(uint32_t depthSlice)
    {
        float farPlane = 2 * m_sceneRadius;
        float sliceThickness = farPlane / (Depth - 1.f);

        float boxFarPlane = depthSlice * sliceThickness;
        float boxNearPlane = (depthSlice - 1) * sliceThickness;

        std::array<Vector3, 6> bounds;
        bounds[0] = { -m_sceneRadius, 0, 0 }; // left
        bounds[1] = { m_sceneRadius, 0, 0 }; // right
        bounds[2] = { 0, m_sceneRadius, 0 }; // top
        bounds[3] = { 0, -m_sceneRadius, 0 }; // bottom
        bounds[4] = { 0, 0, -boxNearPlane }; // near
        bounds[5] = { 0, 0, -boxFarPlane }; // far

        DirectX::BoundingBox lightSpaceAABB;
        DirectX::BoundingBox::CreateFromPoints(lightSpaceAABB,
            bounds.size(),
            bounds.data(),
            sizeof(Vector3)
        );

        DirectX::BoundingOrientedBox worldSpaceBB;
        DirectX::BoundingOrientedBox::CreateFromBoundingBox(worldSpaceBB, lightSpaceAABB);
        worldSpaceBB.Transform(worldSpaceBB, m_shadowMapViewInverse);

        return worldSpaceBB;
    }

    void VolShadowMap::Render(ID3D12GraphicsCommandList* cl, DrawFn fn)
    {
        cl->RSSetViewports(1, &m_shadowMapViewport);

        m_texture3D.Transition(cl, D3D12_RESOURCE_STATE_COPY_DEST);
        m_texture2D.Transition(cl, D3D12_RESOURCE_STATE_RENDER_TARGET);

        auto rtvHandle = m_rtv->GetCPUHandle();
        cl->ClearRenderTargetView(rtvHandle,
            DirectX::ColorsLinear::Black,
            0, nullptr
        );

        D3D12_TEXTURE_COPY_LOCATION dstLocation = {};
        dstLocation.pResource = m_texture3D.Get();
        dstLocation.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
        dstLocation.SubresourceIndex = D3D12CalcSubresource(0, 0, 0, 1, 1);

        D3D12_TEXTURE_COPY_LOCATION srcLocation = {};
        srcLocation.pResource = m_texture2D.Get();
        srcLocation.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
        srcLocation.SubresourceIndex = 0;

        m_texture3D.Transition(cl, D3D12_RESOURCE_STATE_COPY_DEST);

        for (uint32_t depthSlice = 0; depthSlice < Depth; depthSlice++)
        {
            m_texture2D.Transition(cl, D3D12_RESOURCE_STATE_RENDER_TARGET);
            cl->OMSetRenderTargets(1, &rtvHandle, FALSE, nullptr);

            if (depthSlice > 0)
            {
                float farPlane = 2 * m_sceneRadius;
                float sliceThickness = farPlane / (Depth - 1.f);

                float boxFarPlane = depthSlice * sliceThickness;
                float boxNearPlane = (depthSlice - 1) * sliceThickness;

                fn(m_shadowMapView, m_shadowMapProj, 
                    GetBoundingBox(depthSlice), boxNearPlane);
            }

            m_texture2D.Transition(cl, D3D12_RESOURCE_STATE_COPY_SOURCE);

            D3D12_BOX srcBox = { 0, 0, Width, Width, 0, 1 }; 
            srcBox.left = 0;
            srcBox.top = 0;
            srcBox.right = Width;
            srcBox.bottom = Width;
            srcBox.front = 0;
            srcBox.back = 1;

            cl->CopyTextureRegion(
                &dstLocation,
                0, 0, depthSlice,
                &srcLocation, &srcBox
            );
        }
    }

    Gradient::GraphicsMemoryManager::DescriptorView
        VolShadowMap::TransitionAndGetSRV(ID3D12GraphicsCommandList* cl)
    {
        m_texture3D.Transition(cl, D3D12_RESOURCE_STATE_ALL_SHADER_RESOURCE);
        return m_srv;
    }

    DirectX::SimpleMath::Matrix VolShadowMap::GetShadowTransform() const
    {
        const static auto t = DirectX::SimpleMath::Matrix(
            0.5f, 0.f, 0.f, 0.f,
            0.f, -0.5f, 0.f, 0.f,
            0.f, 0.f, 1.f, 0.f,
            0.5f, 0.5f, 0.f, 1.f
        );

        return m_shadowMapView * m_shadowMapProj * t;
    }
}