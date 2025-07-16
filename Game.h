//
// Game.h
//

#pragma once

#include "DeviceResources.h"
#include "StepTimer.h"

#include <memory>

#include <directxtk12/Keyboard.h>
#include <directxtk12/Mouse.h>
#include <directxtk12/SimpleMath.h>
#include <directxtk12/Effects.h>
#include <directxtk12/GeometricPrimitive.h>
#include <directxtk12/CommonStates.h>
#include <directxtk12/PostProcess.h>
#include <FidelityFX/host/backends/dx12/ffx_dx12.h>
#include <FidelityFX/host/ffx_parallelsort.h>

#include "Gradient/FreeMoveCamera.h"
#include "Gradient/Rendering/RenderTexture.h"
#include "Gradient/PipelineState.h"
#include "Gradient/RootSignature.h"
#include "Gradient/BufferManager.h"
#include "Core/VolShadowMap.h"
#include "Core/ShadowMap.h"
#include "Core/PropPipeline.h"


// A basic game implementation that creates a D3D12 device and
// provides a game loop.
class Game final : public DX::IDeviceNotify
{
public:
    const float BrightnessScale = 10.f;
    const int MaxParticles = 65535;

    struct __declspec(align(16)) Constants
    {
        DirectX::XMMATRIX TargetWorld;
        DirectX::XMMATRIX View;
        DirectX::XMMATRIX Proj;
        DirectX::XMMATRIX InverseViewProj;
        DirectX::XMMATRIX VolumetricShadowTransform;
        DirectX::XMMATRIX ShadowTransform;
        DirectX::XMFLOAT4 CullingFrustumPlanes[6];
        float NearPlane;
        DirectX::XMFLOAT3 Albedo;

        float Extinction;
        DirectX::XMFLOAT3 CameraPosition;

        float LightBrightness;
        DirectX::XMFLOAT3 LightDirection;

        float ScatteringAsymmetry;
        DirectX::XMFLOAT3 LightColor;

        float TotalTime;
        float NumInstances;
        float DeltaTime;
        float DidShoot = 0;

        DirectX::XMFLOAT3 ShootRayStart = { 0, 0, 0 };
        float FarPlane;
        DirectX::XMFLOAT3 ShootRayEnd = { 1, 1, 1 };
        float DebugVolShadows = 0;

        float ExtinctionFalloffRadius = 1.f;
        float Scale = 3.f;
        float Anisotropy = 0.2f;
        uint32_t RenderingMethod = 0;
    };

    struct __declspec(align(16)) InstanceData
    {
        DirectX::XMFLOAT3 Position;
        float AbsorptionScale;
        DirectX::XMFLOAT3 Velocity;
        float Mass;
        DirectX::XMFLOAT3 TargetPosition;
        float Pad;
        DirectX::XMFLOAT4 RotationQuat;
    };


    Game() noexcept(false);
    ~Game();

    Game(Game&&) = default;
    Game& operator= (Game&&) = default;

    Game(Game const&) = delete;
    Game& operator= (Game const&) = delete;

    // Initialization and management
    void Initialize(HWND window, int width, int height);

    // Basic game loop
    void Tick();

    // IDeviceNotify
    void OnDeviceLost() override;
    void OnDeviceRestored() override;

    // Messages
    void OnActivated();
    void OnDeactivated();
    void OnSuspending();
    void OnResuming();
    void OnWindowMoved();
    void OnDisplayChange();
    void OnWindowSizeChanged(int width, int height);

    void CleanupResources();

    // Properties
    void GetDefaultSize( int& width, int& height ) const noexcept;

private:

    void Update(DX::StepTimer const& timer);
    void Render();

    void ClearAndSetHDRTarget();
    void ClearAndSetBackBufferTarget();


    void CreateDeviceDependentResources();
    void CreateWindowSizeDependentResources();
    void CreateTetrahedronInstances();

    void SimulateParticles(ID3D12GraphicsCommandList6* cl, const Constants& constants);
    void WriteSortingKeys(ID3D12GraphicsCommandList6* cl, const Constants& constants);
    void DispatchParallelSort(ID3D12GraphicsCommandList6* cl,
        Gradient::BufferManager::InstanceBufferEntry* keys,
        Gradient::BufferManager::InstanceBufferEntry* payload);
    void RenderPropShadows(ID3D12GraphicsCommandList6* cl,
        DirectX::SimpleMath::Vector3 lightDirection);
    void RenderProps(ID3D12GraphicsCommandList6* cl, 
        DirectX::SimpleMath::Vector3 lightDirection);
    void RenderVolumetricShadows(ID3D12GraphicsCommandList6* cl,
        const Constants& constants);
    void RenderParticles(ID3D12GraphicsCommandList6* cl,
        const Constants& constants);
    void RenderGUI(ID3D12GraphicsCommandList6* cl);

    // Device resources.
    std::unique_ptr<DX::DeviceResources>        m_deviceResources;

    // Rendering loop timer.
    DX::StepTimer                               m_timer;

    std::unique_ptr<DirectX::Keyboard> m_keyboard;
    std::unique_ptr<DirectX::Mouse> m_mouse;
    DirectX::Mouse::ButtonStateTracker m_mouseButtonTracker;
    Gradient::FreeMoveCamera m_camera;
    std::unique_ptr<DirectX::CommonStates> m_states;


    Gradient::BufferManager::MeshHandle m_floor;
    Gradient::BufferManager::MeshHandle m_box;

    DirectX::SimpleMath::Matrix m_boxWorld;
    DirectX::SimpleMath::Matrix m_floorWorld;

    std::unique_ptr<ISV::PropPipeline> m_propPipeline;

    std::unique_ptr<Gradient::Rendering::RenderTexture> m_renderTarget;
    std::unique_ptr<DirectX::ToneMapPostProcess> m_tonemapper;
    std::unique_ptr<DirectX::ToneMapPostProcess> m_tonemapperHDR10;
    Gradient::BufferManager::InstanceBufferHandle m_tetInstances;
    Gradient::BufferManager::InstanceBufferHandle m_tetKeys;
    Gradient::BufferManager::InstanceBufferHandle m_tetIndices;
    Gradient::GraphicsMemoryManager::DescriptorView m_tetInstancesUAV;
    Gradient::GraphicsMemoryManager::DescriptorView m_tetKeysUAV;
    Gradient::GraphicsMemoryManager::DescriptorView m_tetIndicesUAV;

    std::unique_ptr<ISV::ShadowMap> m_shadowMap;
    std::unique_ptr<ISV::VolShadowMap> m_volShadowMap;

    Gradient::RootSignature m_tetRS;
    std::unique_ptr<Gradient::PipelineState> m_tetPSO;

    // Shadows use tetRS
    std::unique_ptr<Gradient::PipelineState> m_shadowPSO;

    Gradient::RootSignature m_keyWritingRS;
    Microsoft::WRL::ComPtr<ID3D12PipelineState> m_keyWritingPSO;

    Gradient::RootSignature m_simulationRS;
    Microsoft::WRL::ComPtr<ID3D12PipelineState> m_simulationPSO;


    DirectX::XMFLOAT3 m_guiAlbedo = { 1.f, 1.f, 1.f };
    float m_guiExtinction = 15.f;

    DirectX::XMFLOAT3 m_guiLightDirection = { 0, -1, 1 };
    float m_guiLightBrightness = 2.f;

    DirectX::XMFLOAT3 m_guiLightColor = { 1, 0.8, 0.4 };
    float m_guiScatteringAsymmetry = 0.4f;

    DirectX::XMFLOAT3 m_guiTargetWorld = { 0, 0, 0 };

    float m_guiScale = 4.f;
    float m_guiAnisotropy = 0.2f;
    float m_guiExtinctionFalloffFactor = 2.f;

    bool m_guiDebugVolShadows = false;

    int m_guiParticleCount = 2000;
    int m_guiRenderingMethod = 2;

    // Bullet shooting state
    bool m_didShoot = false;
    DirectX::SimpleMath::Vector3 m_bulletRayStart;
    DirectX::SimpleMath::Vector3 m_bulletRayEnd;

    // FFX stuff

    std::vector<byte> m_ffxScratchMemory;
    FfxInterface m_ffxInterface;
    FfxParallelSortContext m_parallelSortContext;

};
