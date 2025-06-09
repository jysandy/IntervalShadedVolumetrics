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


// A basic game implementation that creates a D3D12 device and
// provides a game loop.
class Game final : public DX::IDeviceNotify
{
public:
    struct __declspec(align(16)) Constants
    {
        DirectX::XMMATRIX TargetWorld;
        DirectX::XMMATRIX View;
        DirectX::XMMATRIX Proj;
        DirectX::XMMATRIX InverseViewProj;
        float NearPlane;
        DirectX::XMFLOAT3 Albedo;

        float Absorption;
        DirectX::XMFLOAT3 CameraPosition;

        float LightBrightness;
        DirectX::XMFLOAT3 LightDirection;

        float ScatteringAsymmetry;
        DirectX::XMFLOAT3 LightColor;

        float TotalTime;
        float NumInstances;
        float DeltaTime;

        float Pad = 0;
    };

    struct __declspec(align(16)) InstanceData
    {
        DirectX::XMFLOAT3 Position;
        float AbsorptionScale;
        DirectX::XMFLOAT3 Velocity;
        float Pad;
        DirectX::XMFLOAT3 TargetPosition;
        float Pad2;
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
    void RenderProps(ID3D12GraphicsCommandList6* cl, 
        DirectX::SimpleMath::Vector3 lightDirection);
    void RenderParticles(ID3D12GraphicsCommandList6* cl,
        const Constants& constants);
    void RenderGUI(ID3D12GraphicsCommandList6* cl);

    // Device resources.
    std::unique_ptr<DX::DeviceResources>        m_deviceResources;

    // Rendering loop timer.
    DX::StepTimer                               m_timer;

    std::unique_ptr<DirectX::Keyboard> m_keyboard;
    std::unique_ptr<DirectX::Mouse> m_mouse;
    Gradient::FreeMoveCamera m_camera;
    std::unique_ptr<DirectX::CommonStates> m_states;


    std::unique_ptr<DirectX::GeometricPrimitive> m_floor;
    std::unique_ptr<DirectX::GeometricPrimitive> m_sphere;
    std::unique_ptr<DirectX::BasicEffect> m_effect;
    std::unique_ptr<Gradient::Rendering::RenderTexture> m_renderTarget;
    std::unique_ptr<DirectX::ToneMapPostProcess> m_tonemapper;
    std::unique_ptr<DirectX::ToneMapPostProcess> m_tonemapperHDR10;
    Gradient::BufferManager::InstanceBufferHandle m_tetInstances;
    Gradient::BufferManager::InstanceBufferHandle m_tetKeys;
    Gradient::BufferManager::InstanceBufferHandle m_tetIndices;
    Gradient::GraphicsMemoryManager::DescriptorView m_tetInstancesUAV;
    Gradient::GraphicsMemoryManager::DescriptorView m_tetKeysUAV;
    Gradient::GraphicsMemoryManager::DescriptorView m_tetIndicesUAV;

    Gradient::RootSignature m_tetRS;
    std::unique_ptr<Gradient::PipelineState> m_tetPSO;

    Gradient::RootSignature m_keyWritingRS;
    Microsoft::WRL::ComPtr<ID3D12PipelineState> m_keyWritingPSO;

    Gradient::RootSignature m_simulationRS;
    Microsoft::WRL::ComPtr<ID3D12PipelineState> m_simulationPSO;


    DirectX::XMFLOAT3 m_guiAlbedo = { 0.8, 0.08, 0.08 };
    float m_guiAbsorption = 1.2f;

    DirectX::XMFLOAT3 m_guiLightDirection = { 0, -0.2, 1 };
    float m_guiLightBrightness = 2.f;

    DirectX::XMFLOAT3 m_guiLightColor = { 1, 0.8, 0.4 };
    float m_guiScatteringAsymmetry = 0.75f;

    DirectX::XMFLOAT3 m_guiTargetWorld = { 0, 0, 0 };

    // FFX stuff

    std::vector<byte> m_ffxScratchMemory;
    FfxInterface m_ffxInterface;
    FfxParallelSortContext m_parallelSortContext;

};
