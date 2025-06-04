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
#include "Gradient/ReadData.h"

extern void ExitGame() noexcept;

using namespace DirectX;
using namespace DirectX::SimpleMath;

using Microsoft::WRL::ComPtr;

Game::Game() noexcept(false)
{
    m_deviceResources = std::make_unique<DX::DeviceResources>(
        DXGI_FORMAT_R10G10B10A2_UNORM,
        DXGI_FORMAT_D32_FLOAT,
        2,
        D3D_FEATURE_LEVEL_12_2,
        DX::DeviceResources::c_AllowTearing | DX::DeviceResources::c_EnableHDR
    );
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

    m_camera.SetPosition({ 0, 0, 20 });

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
    m_world = Matrix::CreateScale(2) * Matrix::CreateRotationZ(cosf(time) * 2.f);

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
    ClearAndSetHDRTarget();

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

    m_effect->SetLightEnabled(0, true);
    m_effect->SetLightDiffuseColor(0, m_guiLightBrightness * Vector3(m_guiLightColor));
    m_effect->SetLightSpecularColor(0, m_guiLightBrightness * Vector3(m_guiLightColor));
    m_effect->SetDiffuseColor({ 0.7, 0.7, 0.7 });
    m_effect->SetSpecularPower(128);
    m_effect->SetAmbientLightColor(0.001 * Vector3(m_guiLightColor));
    auto lightDirection = Vector3(m_guiLightDirection);
    lightDirection.Normalize();
    m_effect->SetLightDirection(0, lightDirection);
    m_effect->SetWorld(Matrix::CreateScale({50, 0.5, 50}) 
        * Matrix::CreateTranslation({0, -10.f, 0}));
    m_effect->SetView(m_camera.GetCamera().GetViewMatrix());
    m_effect->SetProjection(m_camera.GetCamera().GetProjectionMatrix());

    m_effect->Apply(cl);

    m_floor->Draw(cl);
    
    m_effect->SetWorld(Matrix::CreateScale({ 1, 1, 1 })
        * Matrix::CreateTranslation({ 0, -5.f, 0 }));
    m_effect->Apply(cl);
    m_sphere->Draw(cl);

    m_tetRS.SetOnCommandList(cl);
    m_tetPSO->Set(cl, true);

    Constants constants;
    constants.World = m_world.Transpose();

    auto view = m_camera.GetCamera().GetViewMatrix() * Matrix::CreateScale({ -1, -1, -1 });
    auto proj = m_camera.GetCamera().GetProjectionMatrix();

    constants.View = view.Transpose();
    constants.Proj = proj.Transpose();
    constants.InverseViewProj = (view * proj).Invert().Transpose();
    constants.NearPlane = 0.1f;
    constants.Albedo = m_guiAlbedo;
    constants.Absorption = m_guiAbsorption;
    constants.CameraPosition = m_camera.GetCamera().GetPosition();
    constants.LightBrightness = m_guiLightBrightness;
    constants.LightDirection = lightDirection;
    constants.ScatteringAsymmetry = m_guiScatteringAsymmetry;
    constants.LightColor = m_guiLightColor;

    m_tetRS.SetCBV(cl, 0, 0, constants);
    m_tetRS.SetStructuredBufferSRV(cl, 0, 0, m_tetInstances);
    
    auto bm = Gradient::BufferManager::Get();
    auto instanceCount = bm->GetInstanceBuffer(m_tetInstances)->InstanceCount;

    cl->DispatchMesh(instanceCount, 1, 1);

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

    ImGui::Begin("Options");

    if (ImGui::TreeNodeEx("Material", ImGuiTreeNodeFlags_DefaultOpen))
    {
        ImGui::ColorEdit3("Albedo", &m_guiAlbedo.x);
        ImGui::SliderFloat("Absorption", &m_guiAbsorption, 0, 10);
        ImGui::SliderFloat("Scattering Asymmetry", &m_guiScatteringAsymmetry, -0.999, 0.999);

        ImGui::TreePop();
    }

    if (ImGui::TreeNodeEx("Light", ImGuiTreeNodeFlags_DefaultOpen))
    {
        ImGui::DragFloat3("Direction", &m_guiLightDirection.x, 0.001f, -1.f, 1.f);
        ImGui::SliderFloat("Brightness", &m_guiLightBrightness, 0, 10);
        ImGui::ColorEdit3("Color", &m_guiLightColor.x);

        ImGui::TreePop();
    }

    ImGui::End();

    ImGui::Render();
    ImGui_ImplDX12_RenderDrawData(ImGui::GetDrawData(),
        cl);

    PIXEndEvent(cl);

    PIXBeginEvent(cl, PIX_COLOR_DEFAULT, L"MSAA resolve and tonemap");

    m_renderTarget->CopyToSingleSampled(cl);
    ClearAndSetBackBufferTarget();


    m_renderTarget->GetSingleSampledBarrierResource()->Transition(cl, D3D12_RESOURCE_STATE_ALL_SHADER_RESOURCE);
    m_tonemapper->SetHDRSourceTexture(m_renderTarget->GetSRV()->GetGPUHandle());
    m_tonemapperHDR10->SetHDRSourceTexture(m_renderTarget->GetSRV()->GetGPUHandle());
    

    switch (m_deviceResources->GetColorSpace())
    {
    default:
        m_tonemapper->Process(cl);
        break;

    case DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020:
        m_tonemapperHDR10->Process(cl);
        break;
    }
    

    PIXEndEvent(cl);

    // Show the new frame.
    PIXBeginEvent(m_deviceResources->GetCommandQueue(), PIX_COLOR_DEFAULT, L"Present");
    m_deviceResources->Present();

    gmm->Commit(m_deviceResources->GetCommandQueue());
    PIXEndEvent(m_deviceResources->GetCommandQueue());
}

// Helper method to clear the back buffers.
void Game::ClearAndSetHDRTarget()
{
    auto commandList = m_deviceResources->GetCommandList();
    PIXBeginEvent(commandList, PIX_COLOR_DEFAULT, L"ClearAndSetHDRTarget");

    // Clear the views.

    m_renderTarget->ClearAndSetAsTarget(commandList);

    // Set the viewport and scissor rect.
    const auto viewport = m_deviceResources->GetScreenViewport();
    const auto scissorRect = m_deviceResources->GetScissorRect();
    commandList->RSSetViewports(1, &viewport);
    commandList->RSSetScissorRects(1, &scissorRect);

    PIXEndEvent(commandList);
}

void Game::ClearAndSetBackBufferTarget()
{
    auto commandList = m_deviceResources->GetCommandList();
    PIXBeginEvent(commandList, PIX_COLOR_DEFAULT, L"ClearAndSetBackBufferTarget");

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

float RandomFloat()
{
    return (rand() % 10000) / 10000.f;
}

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

    D3D12_FEATURE_DATA_D3D12_OPTIONS7 features = {};
    if (FAILED(device->CheckFeatureSupport(D3D12_FEATURE_D3D12_OPTIONS7, &features, sizeof(features)))
        || (features.MeshShaderTier == D3D12_MESH_SHADER_TIER_NOT_SUPPORTED))
    {
        OutputDebugStringA("ERROR: Mesh Shaders aren't supported!\n");
        throw std::exception("This application makes use of mesh shaders, which are not supported by this graphics device. The application will now exit.");
    }

    Gradient::GraphicsMemoryManager::Initialize(device);
    Gradient::BufferManager::Initialize();

    m_floor = GeometricPrimitive::CreateBox({1, 1, 1});
    m_sphere = GeometricPrimitive::CreateSphere();

    m_world = Matrix::Identity;

    m_states = std::make_unique<DirectX::CommonStates>(device);

    RenderTargetState backBufferRTState(m_deviceResources->GetBackBufferFormat(),
        m_deviceResources->GetDepthBufferFormat());

    m_tonemapper = std::make_unique<ToneMapPostProcess>(device, backBufferRTState,
        ToneMapPostProcess::ACESFilmic,
        ToneMapPostProcess::SRGB);

    m_tonemapperHDR10 = std::make_unique<ToneMapPostProcess>(device,
        backBufferRTState,
        ToneMapPostProcess::None, 
        ToneMapPostProcess::ST2084);

    // Initialize ImGUI

    ImGui_ImplDX12_InitInfo initInfo = {};
    initInfo.Device = device;
    initInfo.CommandQueue = cq;
    initInfo.NumFramesInFlight = 2;
    initInfo.RTVFormat = DXGI_FORMAT_R16G16B16A16_FLOAT;

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

    // PSO and root signature
    m_tetRS.AddCBV(0, 0);
    m_tetRS.AddRootSRV(0, 0); // instances
    m_tetRS.Build(device);

    D3DX12_MESH_SHADER_PIPELINE_STATE_DESC psoDesc = Gradient::PipelineState::GetDefaultMeshDesc();

    auto msData = DX::ReadData(L"Tetrahedron_MS.cso");
    auto psData = DX::ReadData(L"Interval_PS.cso");

    psoDesc.pRootSignature = m_tetRS.Get();
    psoDesc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
    // TODO: Maybe reverse the winding order in the mesh shader instead of doing this?
    psoDesc.RasterizerState = DirectX::CommonStates::CullNone;

    auto blendState = CD3DX12_BLEND_DESC(CD3DX12_DEFAULT());
    blendState.RenderTarget[0].BlendEnable = TRUE;
    blendState.RenderTarget[0].BlendOp = D3D12_BLEND_OP_ADD;
    blendState.RenderTarget[0].SrcBlend = D3D12_BLEND_ONE;
    blendState.RenderTarget[0].DestBlend = D3D12_BLEND_SRC1_COLOR;

    psoDesc.BlendState = blendState;
    psoDesc.MS = { msData.data(), msData.size() };
    psoDesc.PS = { psData.data(), psData.size() };

    m_tetPSO = std::make_unique<Gradient::PipelineState>(psoDesc);
    m_tetPSO->Build(device);

    CreateTetrahedronInstances();
}

// Allocate all memory resources that change on a window SizeChanged event.
void Game::CreateWindowSizeDependentResources()
{
    auto device = m_deviceResources->GetD3DDevice();

    auto size = m_deviceResources->GetOutputSize();
    auto width = static_cast<UINT>(size.right);
    auto height = static_cast<UINT>(size.bottom);

    m_camera.SetAspectRatio((float)width / (float)height);

    m_renderTarget = std::make_unique<Gradient::Rendering::RenderTexture>(
        device,
        width,
        height,
        DXGI_FORMAT_R16G16B16A16_FLOAT,
        true
    );

    RenderTargetState rtState(m_renderTarget->GetRenderTargetFormat(),
        m_renderTarget->GetDepthBufferFormat(),
        m_renderTarget->GetSampleCount());

    EffectPipelineStateDescription pd(
        &GeometricPrimitive::VertexType::InputLayout,
        CommonStates::Opaque,
        CommonStates::DepthDefault,
        CommonStates::CullNone,
        rtState);

    m_effect = std::make_unique<BasicEffect>(device, EffectFlags::Lighting, pd); 
}

void Game::CreateTetrahedronInstances()
{
    auto device = m_deviceResources->GetD3DDevice();
    auto cq = m_deviceResources->GetCommandQueue();

    // Create instances

    std::vector<Gradient::BufferManager::InstanceData> instances;
    for (int i = 0; i < 5000; i++)
    {
        Vector3 position;
        position.x = RandomFloat() * 10.f - 5.f;
        position.y = RandomFloat() * 10.f - 5.f;
        position.z = RandomFloat() * 10.f - 5.f;

        instances.push_back({ position });
    }

    std::sort(instances.begin(), instances.end(),
        [](Gradient::BufferManager::InstanceData a, Gradient::BufferManager::InstanceData b)
        {
            // Sort by lowest Z first.
            // Works as long as we're looking down -ve Z.
            return a.Position.z < b.Position.z;
        });

    auto bm = Gradient::BufferManager::Get();
    m_tetInstances = bm->CreateInstanceBuffer(device, cq, instances);
}

void Game::CleanupResources()
{
    m_floor.reset();
    m_effect.reset();
    m_renderTarget.reset();
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
