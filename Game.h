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

#include "Gradient/FreeMoveCamera.h"
#include "Gradient/Rendering/RenderTexture.h"
#include "Gradient/PipelineState.h"
#include "Gradient/RootSignature.h"


// A basic game implementation that creates a D3D12 device and
// provides a game loop.
class Game final : public DX::IDeviceNotify
{
public:
    struct __declspec(align(16)) Constants
    {
        DirectX::XMMATRIX World;
        DirectX::XMMATRIX View;
        DirectX::XMMATRIX Proj;
        float NearPlane;
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

    // Device resources.
    std::unique_ptr<DX::DeviceResources>        m_deviceResources;

    // Rendering loop timer.
    DX::StepTimer                               m_timer;

    std::unique_ptr<DirectX::Keyboard> m_keyboard;
    std::unique_ptr<DirectX::Mouse> m_mouse;
    Gradient::FreeMoveCamera m_camera;
    std::unique_ptr<DirectX::CommonStates> m_states;


    DirectX::SimpleMath::Matrix m_world;

    std::unique_ptr<DirectX::GeometricPrimitive> m_shape;
    std::unique_ptr<DirectX::BasicEffect> m_effect;
    std::unique_ptr<Gradient::Rendering::RenderTexture> m_renderTarget;
    std::unique_ptr<DirectX::ToneMapPostProcess> m_tonemapper;
    std::unique_ptr<DirectX::ToneMapPostProcess> m_tonemapperHDR10;

    Gradient::RootSignature m_tetRS;
    std::unique_ptr<Gradient::PipelineState> m_tetPSO;
};
