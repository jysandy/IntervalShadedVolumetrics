//
// Game.cpp
//

#include "pch.h"
#include "Game.h"

#include <directxtk12/CommonStates.h>

#include <imgui.h>
#include "imgui_impl_win32.h"
#include "imgui_impl_dx12.h"

#include "Gradient/GraphicsMemoryManager.h"

extern void ExitGame() noexcept;

using namespace DirectX;
using namespace DirectX::SimpleMath;

using Microsoft::WRL::ComPtr;

Game::Game() noexcept(false)
{
    m_deviceResources = std::make_unique<DX::DeviceResources>();
    // TODO: Provide parameters for swapchain format, depth/stencil format, and backbuffer count.
    //   Add DX::DeviceResources::c_AllowTearing to opt-in to variable rate displays.
    //   Add DX::DeviceResources::c_EnableHDR for HDR10 display.
    //   Add DX::DeviceResources::c_ReverseDepth to optimize depth buffer clears for 0 instead of 1.
    m_deviceResources->RegisterDeviceNotify(this);
}

Game::~Game()
{
    if (m_deviceResources)
    {
        m_deviceResources->WaitForGpu();
    }

    CleanupResources();
}

// Initialize the Direct3D resources required to run.
void Game::Initialize(HWND window, int width, int height)
{
    m_keyboard = std::make_unique<Keyboard>();
    m_mouse = std::make_unique<Mouse>();
    m_mouse->SetWindow(window);
    m_mouse->SetMode(DirectX::Mouse::MODE_ABSOLUTE);

    m_deviceResources->SetWindow(window, width, height);

    m_deviceResources->CreateDeviceResources();
    CreateDeviceDependentResources();

    m_deviceResources->CreateWindowSizeDependentResources();
    CreateWindowSizeDependentResources();

    // TODO: Change the timer settings if you want something other than the default variable timestep mode.
    // e.g. for 60 FPS fixed timestep update logic, call:
    /*
    m_timer.SetFixedTimeStep(true);
    m_timer.SetTargetElapsedSeconds(1.0 / 60);
    */
}

#pragma region Frame Update
// Executes the basic game loop.
void Game::Tick()
{
    m_timer.Tick([&]()
    {
        Update(m_timer);
    });

    Render();
}

// Updates the world.
void Game::Update(DX::StepTimer const& timer)
{
    PIXBeginEvent(PIX_COLOR_DEFAULT, L"Update");

    m_camera.Update(timer);

    auto time = static_cast<float>(timer.GetTotalSeconds());

    m_world = Matrix::CreateRotationZ(cosf(time) * 2.f);

    PIXEndEvent();
}
#pragma endregion

#pragma region Frame Render
// Draws the scene.
void Game::Render()
{
    auto gmm = Gradient::GraphicsMemoryManager::Get();

    // Don't try to render anything before the first Update.
    if (m_timer.GetFrameCount() == 0)
    {
        return;
    }


    // Prepare the command list to render a new frame.
    m_deviceResources->Prepare();
    Clear();

    auto cl = m_deviceResources->GetCommandList();

    ID3D12DescriptorHeap* heaps[] = { gmm->GetSrvUavDescriptorHeap(), m_states->Heap() };
    cl->SetDescriptorHeaps(static_cast<UINT>(std::size(heaps)), heaps);

    D3D12_RECT scissorRect;
    scissorRect.left = 0;
    scissorRect.top = 0;
    scissorRect.right = LONG_MAX; // Large value ensures no clipping
    scissorRect.bottom = LONG_MAX;

    cl->RSSetScissorRects(1, &scissorRect);


    PIXBeginEvent(cl, PIX_COLOR_DEFAULT, L"Render");

    m_effect->SetWorld(m_world);
    m_effect->SetView(m_camera.GetCamera().GetViewMatrix());
    m_effect->SetProjection(m_camera.GetCamera().GetProjectionMatrix());

    m_effect->Apply(cl);

    m_shape->Draw(cl);

    PIXEndEvent(cl);

    PIXBeginEvent(cl, PIX_COLOR_DEFAULT, L"GUI");

    ImGui_ImplDX12_NewFrame();
    ImGui_ImplWin32_NewFrame();
    ImGui::NewFrame();

    ImGui::Begin("Performance");

    float fps = m_timer.GetFramesPerSecond();

    ImGui::Text("FPS: %.2f", fps);
    ImGui::Text("msPF: %.2f", 1000.f / fps);

    ImGui::End();


    ImGui::Render();
    ImGui_ImplDX12_RenderDrawData(ImGui::GetDrawData(),
        cl);

    PIXEndEvent(cl);

    // Show the new frame.
    PIXBeginEvent(m_deviceResources->GetCommandQueue(), PIX_COLOR_DEFAULT, L"Present");
    m_deviceResources->Present();

    gmm->Commit(m_deviceResources->GetCommandQueue());
    PIXEndEvent(m_deviceResources->GetCommandQueue());
}

// Helper method to clear the back buffers.
void Game::Clear()
{
    auto commandList = m_deviceResources->GetCommandList();
    PIXBeginEvent(commandList, PIX_COLOR_DEFAULT, L"Clear");

    // Clear the views.
    const auto rtvDescriptor = m_deviceResources->GetRenderTargetView();
    const auto dsvDescriptor = m_deviceResources->GetDepthStencilView();

    commandList->OMSetRenderTargets(1, &rtvDescriptor, FALSE, &dsvDescriptor);
    commandList->ClearRenderTargetView(rtvDescriptor, Colors::CornflowerBlue, 0, nullptr);
    commandList->ClearDepthStencilView(dsvDescriptor, D3D12_CLEAR_FLAG_DEPTH, 1.0f, 0, 0, nullptr);

    // Set the viewport and scissor rect.
    const auto viewport = m_deviceResources->GetScreenViewport();
    const auto scissorRect = m_deviceResources->GetScissorRect();
    commandList->RSSetViewports(1, &viewport);
    commandList->RSSetScissorRects(1, &scissorRect);

    PIXEndEvent(commandList);
}
#pragma endregion

#pragma region Message Handlers
// Message handlers
void Game::OnActivated()
{
    // TODO: Game is becoming active window.
}

void Game::OnDeactivated()
{
    // TODO: Game is becoming background window.
}

void Game::OnSuspending()
{
    // TODO: Game is being power-suspended (or minimized).
}

void Game::OnResuming()
{
    m_timer.ResetElapsedTime();

    // TODO: Game is being power-resumed (or returning from minimize).
}

void Game::OnWindowMoved()
{
    const auto r = m_deviceResources->GetOutputSize();
    m_deviceResources->WindowSizeChanged(r.right, r.bottom);
}

void Game::OnDisplayChange()
{
    m_deviceResources->UpdateColorSpace();
}

void Game::OnWindowSizeChanged(int width, int height)
{
    if (!m_deviceResources->WindowSizeChanged(width, height))
        return;

    CreateWindowSizeDependentResources();

    // TODO: Game window is being resized.
}

// Properties
void Game::GetDefaultSize(int& width, int& height) const noexcept
{
    width = 1920;
    height = 1080;
}
#pragma endregion

#pragma region Direct3D Resources
// These are the resources that depend on the device.
void Game::CreateDeviceDependentResources()
{
    auto device = m_deviceResources->GetD3DDevice();
    auto cq = m_deviceResources->GetCommandQueue();

    // Check Shader Model 6 support
    D3D12_FEATURE_DATA_SHADER_MODEL shaderModel = { D3D_SHADER_MODEL_6_8 };
    if (FAILED(device->CheckFeatureSupport(D3D12_FEATURE_SHADER_MODEL, &shaderModel, sizeof(shaderModel)))
        || (shaderModel.HighestShaderModel < D3D_SHADER_MODEL_6_8))
    {
#ifdef _DEBUG
        OutputDebugStringA("ERROR: Shader Model 6.8 is not supported!\n");
#endif
        throw std::runtime_error("Shader Model 6.8 is not supported!");
    }

    Gradient::GraphicsMemoryManager::Initialize(device);

    RenderTargetState rtState(m_deviceResources->GetBackBufferFormat(),
        m_deviceResources->GetDepthBufferFormat());

    EffectPipelineStateDescription pd(
        &GeometricPrimitive::VertexType::InputLayout,
        CommonStates::Opaque,
        CommonStates::DepthDefault,
        CommonStates::CullNone,
        rtState);

    m_effect = std::make_unique<BasicEffect>(device, EffectFlags::Lighting, pd);
    m_effect->EnableDefaultLighting();

    m_shape = GeometricPrimitive::CreateBox({1, 1, 1});

    m_world = Matrix::Identity;

    m_states = std::make_unique<DirectX::CommonStates>(device);

    // Initialize ImGUI

    ImGui_ImplDX12_InitInfo initInfo = {};
    initInfo.Device = device;
    initInfo.CommandQueue = cq;
    initInfo.NumFramesInFlight = 2;
    initInfo.RTVFormat = m_deviceResources->GetBackBufferFormat();

    auto gmm = Gradient::GraphicsMemoryManager::Get();
    initInfo.SrvDescriptorHeap = gmm->GetSrvUavDescriptorHeap();
    initInfo.SrvDescriptorAllocFn
        = [](ImGui_ImplDX12_InitInfo*,
            D3D12_CPU_DESCRIPTOR_HANDLE* outCpuHandle,
            D3D12_GPU_DESCRIPTOR_HANDLE* outGpuHandle)
        {
            auto gmm = Gradient::GraphicsMemoryManager::Get();
            auto index = gmm->AllocateSrvOrUav();
            *outCpuHandle = gmm->GetSRVOrUAVCpuHandle(index);
            *outGpuHandle = gmm->GetSRVOrUAVGpuHandle(index);
        };
    initInfo.SrvDescriptorFreeFn
        = [](ImGui_ImplDX12_InitInfo*,
            D3D12_CPU_DESCRIPTOR_HANDLE cpuHandle,
            D3D12_GPU_DESCRIPTOR_HANDLE gpuHandle)
        {
            auto gmm = Gradient::GraphicsMemoryManager::Get();
            gmm->FreeSrvByCpuHandle(cpuHandle);
        };


    ImGui_ImplDX12_Init(&initInfo);
}

// Allocate all memory resources that change on a window SizeChanged event.
void Game::CreateWindowSizeDependentResources()
{
    auto size = m_deviceResources->GetOutputSize();

    m_camera.SetAspectRatio((float)size.right / (float)size.bottom);
}

void Game::CleanupResources()
{
    m_shape.reset();
    m_effect.reset();
    Gradient::GraphicsMemoryManager::Shutdown();
}

void Game::OnDeviceLost()
{
    // TODO: Add Direct3D resource cleanup here.
    CleanupResources();
}

void Game::OnDeviceRestored()
{
    CreateDeviceDependentResources();

    CreateWindowSizeDependentResources();
}
#pragma endregion
