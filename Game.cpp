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
#include "Gradient/Math.h"

extern void ExitGame() noexcept;

using namespace DirectX;
using namespace DirectX::SimpleMath;

using Microsoft::WRL::ComPtr;

inline void ThrowIfFfxFailed(FfxErrorCode error)
{
    if (error != FFX_OK)
    {
        throw std::runtime_error("FFX failed with code: " + std::to_string(error));
    }
}

Microsoft::WRL::ComPtr<ID3D12PipelineState> CreateComputePipelineState(
    ID3D12Device* device,
    const std::wstring& shaderPath,
    ID3D12RootSignature* rootSignature
)
{
    Microsoft::WRL::ComPtr<ID3D12PipelineState> out;

    auto csData = DX::ReadData(shaderPath.c_str());
    D3D12_COMPUTE_PIPELINE_STATE_DESC psoDesc = {};
    psoDesc.pRootSignature = rootSignature;
    psoDesc.CS = { csData.data(), csData.size() };
    DX::ThrowIfFailed(
        device->CreateComputePipelineState(&psoDesc, IID_PPV_ARGS(out.ReleaseAndGetAddressOf())));

    return out;
}

Game::Game() noexcept(false)
{
    m_deviceResources = std::make_unique<DX::DeviceResources>(
        DXGI_FORMAT_R10G10B10A2_UNORM,
        DXGI_FORMAT_D32_FLOAT,
        2,
        D3D_FEATURE_LEVEL_12_2,
        DX::DeviceResources::c_AllowTearing
        //| DX::DeviceResources::c_EnableHDR
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
    DirectX::Keyboard::Get().Reset();
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

    auto mouseState = DirectX::Mouse::Get().GetState();
    m_mouseButtonTracker.Update(mouseState);

    m_camera.Update(timer, mouseState);

    if (mouseState.positionMode == DirectX::Mouse::MODE_ABSOLUTE
        && m_mouseButtonTracker.leftButton == DirectX::Mouse::ButtonStateTracker::HELD)
    {
        auto size = m_deviceResources->GetOutputSize();
        Vector2 mousePosition = { (float)mouseState.x / size.right,
            (float)mouseState.y / size.bottom };
        mousePosition = mousePosition * 2 - Vector2(1, 1);
        mousePosition.y *= -1;

        auto view = m_camera.GetCamera().GetViewMatrix();
        auto proj = m_camera.GetCamera().GetProjectionMatrix();

        auto unproject = (view * proj).Invert();

        Vector3 rayStart = { mousePosition.x, mousePosition.y, 0 };
        Vector3 rayEnd = { mousePosition.x, mousePosition.y, 1 };

        m_bulletRayStart = Vector3::Transform(rayStart, unproject);
        m_bulletRayEnd = Vector3::Transform(rayEnd, unproject);
        m_didShoot = true;
    }
    else
    {
        m_didShoot = false;
    }


    auto time = static_cast<float>(timer.GetTotalSeconds());

    PIXEndEvent();
}
#pragma endregion


#pragma region Frame Render

void Game::WriteSortingKeys(ID3D12GraphicsCommandList6* cl,
    const Constants& constants)
{
    auto bm = Gradient::BufferManager::Get();

    bm->GetInstanceBuffer(m_tetInstances)->Resource.Transition(cl, D3D12_RESOURCE_STATE_ALL_SHADER_RESOURCE);
    bm->GetInstanceBuffer(m_tetKeys)->Resource.Transition(cl, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    bm->GetInstanceBuffer(m_tetIndices)->Resource.Transition(cl, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);

    m_keyWritingRS.SetOnCommandList(cl);
    cl->SetPipelineState(m_keyWritingPSO.Get());

    m_keyWritingRS.SetCBV(cl, 0, 0, constants);
    m_keyWritingRS.SetStructuredBufferSRV(cl, 0, 0, m_tetInstances);
    m_keyWritingRS.SetUAV(cl, 0, 0, m_tetKeysUAV);
    m_keyWritingRS.SetUAV(cl, 1, 0, m_tetIndicesUAV);

    cl->Dispatch(
        Gradient::Math::DivRoundUp(
            m_guiParticleCount,
            32u),
        1, 1);
}

void Game::DispatchParallelSort(ID3D12GraphicsCommandList6* cl,
    Gradient::BufferManager::InstanceBufferEntry* keys,
    Gradient::BufferManager::InstanceBufferEntry* payload)
{
    auto bm = Gradient::BufferManager::Get();

    keys->Resource.Transition(cl, D3D12_RESOURCE_STATE_ALL_SHADER_RESOURCE);
    payload->Resource.Transition(cl, D3D12_RESOURCE_STATE_ALL_SHADER_RESOURCE);

    FfxParallelSortDispatchDescription dispatchDesc = {};

    auto resourceDesc = ffxGetResourceDescriptionDX12(keys->Resource.Get(),
        FFX_RESOURCE_USAGE_UAV);
    resourceDesc.format = FfxSurfaceFormat::FFX_SURFACE_FORMAT_R32_FLOAT;
    resourceDesc.stride = sizeof(float);
    dispatchDesc.commandList = ffxGetCommandListDX12(cl);
    dispatchDesc.keyBuffer = ffxGetResourceDX12(keys->Resource.Get(),
        resourceDesc,
        L"Tetrahedron_KeyBuffer",
        FFX_RESOURCE_STATE_PIXEL_COMPUTE_READ
    );

    auto payloadResourceDesc = ffxGetResourceDescriptionDX12(
        payload->Resource.Get(), FFX_RESOURCE_USAGE_UAV);
    payloadResourceDesc.format = FFX_SURFACE_FORMAT_R32_UINT;
    payloadResourceDesc.stride = sizeof(uint32_t);
    dispatchDesc.payloadBuffer = ffxGetResourceDX12(
        payload->Resource.Get(),
        payloadResourceDesc,
        L"Tetrahedron_PayloadBuffer",
        FFX_RESOURCE_STATE_PIXEL_COMPUTE_READ
    );
    dispatchDesc.numKeysToSort = m_guiParticleCount;

    ThrowIfFfxFailed(ffxParallelSortContextDispatch(&m_parallelSortContext, &dispatchDesc));
}

void Game::RenderProps(ID3D12GraphicsCommandList6* cl,
    Vector3 normalizedLightDirection)
{
    m_effect->SetLightEnabled(0, true);
    m_effect->SetLightDiffuseColor(0, m_guiLightBrightness * BrightnessScale * Vector3(m_guiLightColor));
    m_effect->SetLightSpecularColor(0, m_guiLightBrightness * BrightnessScale * Vector3(m_guiLightColor));
    m_effect->SetDiffuseColor({ 0.7, 0.7, 0.7 });
    m_effect->SetSpecularPower(128);
    m_effect->SetAmbientLightColor(0.001 * Vector3(m_guiLightColor));
    m_effect->SetLightDirection(0, normalizedLightDirection);
    m_effect->SetWorld(Matrix::CreateScale({ 50, 0.5, 50 })
        * Matrix::CreateTranslation({ 0, -10.f, 0 }));
    m_effect->SetView(m_camera.GetCamera().GetViewMatrix());
    m_effect->SetProjection(m_camera.GetCamera().GetProjectionMatrix());

    m_effect->Apply(cl);

    m_floor->Draw(cl);

    m_effect->SetWorld(Matrix::CreateScale({ 1, 1, 1 })
        * Matrix::CreateTranslation({ 0, -5.f, 0 }));
    m_effect->Apply(cl);
    m_sphere->Draw(cl);
}

void Game::RenderParticles(ID3D12GraphicsCommandList6* cl,
    const Constants& constants)
{
    auto bm = Gradient::BufferManager::Get();

    bm->GetInstanceBuffer(m_tetInstances)->Resource.Transition(
        cl, D3D12_RESOURCE_STATE_ALL_SHADER_RESOURCE);
    bm->GetInstanceBuffer(m_tetIndices)->Resource.Transition(
        cl, D3D12_RESOURCE_STATE_ALL_SHADER_RESOURCE);

    m_tetRS.SetOnCommandList(cl);
    m_tetPSO->Set(cl, false);

    m_tetRS.SetCBV(cl, 0, 0, constants);
    m_tetRS.SetStructuredBufferSRV(cl, 0, 0, m_tetInstances);
    m_tetRS.SetStructuredBufferSRV(cl, 1, 0, m_tetIndices);
    m_tetRS.SetSRV(cl, 2, 0, m_volShadowMap->TransitionAndGetSRV(cl));

    cl->DispatchMesh(
        Gradient::Math::DivRoundUp(
            m_guiParticleCount,
            32),
        1, 1);
}

void Game::RenderVolumetricShadows(ID3D12GraphicsCommandList6* cl,
    const Constants& constants)
{
    auto bm = Gradient::BufferManager::Get();

    m_tetRS.SetOnCommandList(cl);
    m_shadowPSO->Set(cl, true);

    bm->GetInstanceBuffer(m_tetInstances)->Resource.Transition(
        cl, D3D12_RESOURCE_STATE_ALL_SHADER_RESOURCE);
    bm->GetInstanceBuffer(m_tetIndices)->Resource.Transition(
        cl, D3D12_RESOURCE_STATE_ALL_SHADER_RESOURCE);

    m_tetRS.SetStructuredBufferSRV(cl, 0, 0, m_tetInstances);
    m_tetRS.SetStructuredBufferSRV(cl, 1, 0, m_tetIndices);

    m_volShadowMap->SetLightDirection(constants.LightDirection);
    m_volShadowMap->Render(cl,
        [constants, &cl, &bm, this](Matrix view, Matrix proj, DirectX::BoundingOrientedBox bb)
        {
            auto newConstants = constants;

            auto v = (view * Matrix::CreateScale({ -1, -1, -1 }));

            newConstants.View = v.Transpose();
            newConstants.Proj = proj.Transpose();
            newConstants.InverseViewProj = (v * proj).Invert().Transpose();
            newConstants.NearPlane = 0;
            auto cullingPlanes
                = Gradient::Math::GetPlanes(bb);
            for (int i = 0; i < 6; i++)
            {
                newConstants.CullingFrustumPlanes[i] = cullingPlanes[i];
            }

            m_tetRS.SetCBV(cl, 0, 0, newConstants);

            cl->DispatchMesh(
                Gradient::Math::DivRoundUp(
                    m_guiParticleCount,
                    32),
                1, 1);
        });
}

void Game::RenderGUI(ID3D12GraphicsCommandList6* cl)
{
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
        ImGui::SliderInt("Particle Count", &m_guiParticleCount, 1, MaxParticles);
        ImGui::SliderFloat("Scale", &m_guiScale, 0.01, 30);
        ImGui::ColorEdit3("Albedo", &m_guiAlbedo.x);
        ImGui::SliderFloat("Extinction", &m_guiExtinction, 0, 30);
        ImGui::SliderFloat("Extinction Falloff", &m_guiExtinctionFalloffFactor, 0, 10);
        ImGui::SliderFloat("Scattering Anisotropy", &m_guiAnisotropy, 0, 1);
        ImGui::SliderFloat("Scattering Asymmetry", &m_guiScatteringAsymmetry, -0.999, 0.999);
        const char* items[] = { "Vanilla", "Faded Extinction (Taylor Series)", "Faded Extinction (Simpson's Rule)"};
        ImGui::Combo("Rendering Method", &m_guiRenderingMethod, items, IM_ARRAYSIZE(items));

        ImGui::TreePop();
    }

    if (ImGui::TreeNodeEx("Light", ImGuiTreeNodeFlags_DefaultOpen))
    {
        ImGui::DragFloat3("Direction", &m_guiLightDirection.x, 0.001f, -1.f, 1.f);
        ImGui::SliderFloat("Brightness", &m_guiLightBrightness, 0, 10);
        ImGui::ColorEdit3("Color", &m_guiLightColor.x);
        ImGui::Checkbox("Debug Volumetric Shadows", &m_guiDebugVolShadows);

        ImGui::TreePop();
    }

    if (ImGui::TreeNodeEx("Simulation", ImGuiTreeNodeFlags_DefaultOpen))
    {
        ImGui::DragFloat3("Target Position", &m_guiTargetWorld.x, 0.05f, -100.f, 100.f);
        ImGui::TreePop();
    }

    ImGui::End();

    ImGui::Render();
    ImGui_ImplDX12_RenderDrawData(ImGui::GetDrawData(),
        cl);
}

void Game::SimulateParticles(ID3D12GraphicsCommandList6* cl, const Constants& constants)
{
    auto bm = Gradient::BufferManager::Get();

    bm->GetInstanceBuffer(m_tetInstances)->Resource.Transition(
        cl, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);

    m_simulationRS.SetOnCommandList(cl);
    cl->SetPipelineState(m_simulationPSO.Get());

    m_simulationRS.SetCBV(cl, 0, 0, constants);
    m_simulationRS.SetUAV(cl, 0, 0, m_tetInstancesUAV);

    cl->Dispatch(
        Gradient::Math::DivRoundUp(
            m_guiParticleCount,
            32u),
        1, 1);
}

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

    auto cl = m_deviceResources->GetCommandList();
    auto bm = Gradient::BufferManager::Get();

    ID3D12DescriptorHeap* heaps[] = { gmm->GetSrvUavDescriptorHeap(), m_states->Heap() };
    cl->SetDescriptorHeaps(static_cast<UINT>(std::size(heaps)), heaps);

    D3D12_RECT scissorRect;
    scissorRect.left = 0;
    scissorRect.top = 0;
    scissorRect.right = LONG_MAX; // Large value ensures no clipping
    scissorRect.bottom = LONG_MAX;

    cl->RSSetScissorRects(1, &scissorRect);

    auto lightDirection = Vector3(m_guiLightDirection);
    lightDirection.Normalize();

    Constants constants;

    auto view = m_camera.GetCamera().GetViewMatrix() * Matrix::CreateScale({ -1, -1, -1 });
    auto proj = m_camera.GetCamera().GetProjectionMatrix();

    auto cullingPlanes
        = Gradient::Math::GetPlanes(m_camera.GetCamera().GetFrustum());

    constants.TargetWorld = Matrix::CreateTranslation(m_guiTargetWorld).Transpose();
    constants.View = view.Transpose();
    constants.Proj = proj.Transpose();
    constants.InverseViewProj = (view * proj).Invert().Transpose();

    for (int i = 0; i < 6; i++)
    {
        constants.CullingFrustumPlanes[i] = cullingPlanes[i];
    }

    constants.NearPlane = m_camera.GetCamera().NearPlane;
    constants.FarPlane = m_camera.GetCamera().FarPlane;
    constants.Albedo = m_guiAlbedo;
    constants.Extinction = m_guiExtinction;
    constants.CameraPosition = m_camera.GetCamera().GetPosition();
    constants.LightBrightness = m_guiLightBrightness * BrightnessScale;
    constants.LightDirection = lightDirection;
    constants.ScatteringAsymmetry = m_guiScatteringAsymmetry;
    constants.LightColor = m_guiLightColor;
    constants.TotalTime = m_timer.GetTotalSeconds();
    constants.DeltaTime = m_timer.GetElapsedSeconds();
    auto instances = bm->GetInstanceBuffer(m_tetInstances);
    constants.NumInstances = m_guiParticleCount;
    constants.DebugVolShadows = m_guiDebugVolShadows ? 1 : 0;
    constants.Scale = m_guiScale;
    constants.ExtinctionFalloffRadius = m_guiScale * m_guiExtinctionFalloffFactor;
    constants.Anisotropy = m_guiAnisotropy;
    constants.RenderingMethod = m_guiRenderingMethod;

    m_volShadowMap->SetLightDirection(constants.LightDirection);
    constants.ShadowTransform = m_volShadowMap->GetShadowTransform().Transpose();

    if (m_didShoot)
    {
        constants.DidShoot = 1;
        constants.ShootRayStart = m_bulletRayStart;
        constants.ShootRayEnd = m_bulletRayEnd;
    }
    else
    {
        constants.DidShoot = 0;
    }

    m_didShoot = 0;


    PIXBeginEvent(cl, PIX_COLOR_DEFAULT, L"Simulate particles");

    SimulateParticles(cl, constants);

    PIXEndEvent(cl);

    PIXBeginEvent(cl, PIX_COLOR_DEFAULT, L"Volumetric shadow rendering");

    RenderVolumetricShadows(cl, constants);

    PIXEndEvent(cl);

    PIXBeginEvent(cl, PIX_COLOR_DEFAULT, L"Sort particles");

    WriteSortingKeys(cl, constants);
    DispatchParallelSort(cl,
        bm->GetInstanceBuffer(m_tetKeys),
        bm->GetInstanceBuffer(m_tetIndices)
    );

    cl->SetDescriptorHeaps(static_cast<UINT>(std::size(heaps)), heaps);
    PIXEndEvent(cl);

    PIXBeginEvent(cl, PIX_COLOR_DEFAULT, L"Render");

    ClearAndSetHDRTarget();
    RenderProps(cl, lightDirection);
    RenderParticles(cl, constants);

    PIXEndEvent(cl);

    PIXBeginEvent(cl, PIX_COLOR_DEFAULT, L"GUI");

    RenderGUI(cl);

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
    //PIXBeginEvent(m_deviceResources->GetCommandQueue(), PIX_COLOR_DEFAULT, L"Present");
    m_deviceResources->Present();

    gmm->Commit(m_deviceResources->GetCommandQueue());
    //PIXEndEvent(m_deviceResources->GetCommandQueue());
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

    m_floor = GeometricPrimitive::CreateBox({ 1, 1, 1 });
    m_sphere = GeometricPrimitive::CreateSphere();

    m_states = std::make_unique<DirectX::CommonStates>(device);

    m_volShadowMap = std::make_unique<ISV::VolShadowMap>(device, 30.f);

    RenderTargetState backBufferRTState(m_deviceResources->GetBackBufferFormat(),
        m_deviceResources->GetDepthBufferFormat());

    m_tonemapper = std::make_unique<ToneMapPostProcess>(device, backBufferRTState,
        ToneMapPostProcess::ACESFilmic,
        ToneMapPostProcess::SRGB);

    m_tonemapperHDR10 = std::make_unique<ToneMapPostProcess>(device,
        backBufferRTState,
        ToneMapPostProcess::None,
        ToneMapPostProcess::ST2084);

    m_tonemapperHDR10->SetST2084Parameter(800);

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

    // Tetrahedron PSO and root signature
    m_tetRS.AddCBV(0, 0);
    m_tetRS.AddRootSRV(0, 0);   // instances
    m_tetRS.AddRootSRV(1, 0);   // indices
    m_tetRS.AddSRV(2, 0);       // volumetric shadow map

    m_tetRS.AddStaticSampler(CD3DX12_STATIC_SAMPLER_DESC(0,
        D3D12_FILTER_MIN_MAG_MIP_LINEAR,
        D3D12_TEXTURE_ADDRESS_MODE_CLAMP,
        D3D12_TEXTURE_ADDRESS_MODE_CLAMP,
        D3D12_TEXTURE_ADDRESS_MODE_CLAMP),
        0, 0);

    m_tetRS.Build(device);

    D3DX12_MESH_SHADER_PIPELINE_STATE_DESC psoDesc = Gradient::PipelineState::GetDefaultMeshDesc();

    auto msData = DX::ReadData(L"Tetrahedron_MS.cso");
    auto psData = DX::ReadData(L"Interval_PS.cso");

    psoDesc.pRootSignature = m_tetRS.Get();
    psoDesc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
    // TODO: Maybe reverse the winding order in the mesh shader instead of doing this?
    psoDesc.RasterizerState = DirectX::CommonStates::CullNone;
    psoDesc.DepthStencilState = DirectX::CommonStates::DepthRead;

    auto blendState = CD3DX12_BLEND_DESC(CD3DX12_DEFAULT());
    blendState.RenderTarget[0].BlendEnable = TRUE;
    blendState.RenderTarget[0].BlendOp = D3D12_BLEND_OP_ADD;
    blendState.RenderTarget[0].SrcBlend = D3D12_BLEND_ONE;
    blendState.RenderTarget[0].DestBlend = D3D12_BLEND_SRC_ALPHA;

    psoDesc.BlendState = blendState;
    psoDesc.MS = { msData.data(), msData.size() };
    psoDesc.PS = { psData.data(), psData.size() };

    m_tetPSO = std::make_unique<Gradient::PipelineState>(psoDesc);
    m_tetPSO->Build(device);

    // Shadow PSO
    auto shadowPSData = DX::ReadData(L"VolShadowMap_PS.cso");

    psoDesc.DepthStencilState = DirectX::CommonStates::DepthNone;
    psoDesc.PS = { shadowPSData.data(), shadowPSData.size() };

    auto shadowBlendState = CD3DX12_BLEND_DESC(CD3DX12_DEFAULT());
    shadowBlendState.RenderTarget[0].BlendEnable = TRUE;
    shadowBlendState.RenderTarget[0].BlendOp = D3D12_BLEND_OP_ADD;
    shadowBlendState.RenderTarget[0].SrcBlend = D3D12_BLEND_ONE;
    shadowBlendState.RenderTarget[0].DestBlend = D3D12_BLEND_ONE;
    psoDesc.BlendState = shadowBlendState;

    m_shadowPSO = std::make_unique<Gradient::PipelineState>(psoDesc);
    m_shadowPSO->Build(device);

    // Key writing PSO and root signature
    m_keyWritingRS.AddCBV(0, 0); // constants
    m_keyWritingRS.AddRootSRV(0, 0); // instances
    m_keyWritingRS.AddUAV(0, 0); // keys
    m_keyWritingRS.AddUAV(1, 0); // indices
    m_keyWritingRS.Build(device, true);

    m_keyWritingPSO = CreateComputePipelineState(device, L"WriteSortingKeys_CS.cso", m_keyWritingRS.Get());

    // Simulation PSO and root signature
    m_simulationRS.AddCBV(0, 0); // constants
    m_simulationRS.AddUAV(0, 0); // instances
    m_simulationRS.Build(device, true);

    m_simulationPSO = CreateComputePipelineState(device,
        L"SimulateParticles_CS.cso",
        m_simulationRS.Get());

    // Set up FidelityFX interface.

    size_t scratchMemorySize = ffxGetScratchMemorySizeDX12(2);
    m_ffxScratchMemory.resize(scratchMemorySize);

    auto ffxDevice = ffxGetDeviceDX12(device);
    ThrowIfFfxFailed(ffxGetInterfaceDX12(&m_ffxInterface,
        ffxDevice,
        m_ffxScratchMemory.data(),
        m_ffxScratchMemory.size(),
        2));


    FfxParallelSortContextDescription contextDesc = {};
    contextDesc.backendInterface = m_ffxInterface;
    contextDesc.maxEntries = 65536;
    contextDesc.flags = FfxParallelSortInitializationFlagBits::FFX_PARALLELSORT_PAYLOAD_SORT;

    ThrowIfFfxFailed(ffxParallelSortContextCreate(&m_parallelSortContext, &contextDesc));

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
    auto gmm = Gradient::GraphicsMemoryManager::Get();

    // Create instances

    std::vector<InstanceData> instances;
    for (int i = 0; i < MaxParticles; i++)
    {
        Vector3 position;
        position.x = RandomFloat() * 10.f - 5.f;
        position.y = RandomFloat() * 10.f - 5.f;
        position.z = RandomFloat() * 10.f - 5.f;

        float densityMultiplier = std::abs(RandomFloat() * 10.f - 5.f);

        Vector3 rotationAxis = { RandomFloat(), RandomFloat(), RandomFloat() };
        rotationAxis = rotationAxis * 2.f - Vector3(1.f, 1.f, 1.f);
        rotationAxis.Normalize();
        float angle = RandomFloat() * DirectX::XM_2PI;

        instances.push_back(
            {
            position + 2.f * rotationAxis,
            densityMultiplier,
            Vector3::Zero,
            densityMultiplier * 0.5f,
            position,
            0,
            Quaternion::CreateFromAxisAngle(rotationAxis, angle)
            });
    }

    auto bm = Gradient::BufferManager::Get();
    m_tetInstances = bm->CreateBuffer(device, cq, instances);
    bm->GetInstanceBuffer(m_tetInstances)->Resource.Get()->SetName(L"Tetrahedron Instances");
    m_tetInstancesUAV = gmm->CreateBufferUAV(device,
        bm->GetInstanceBuffer(m_tetInstances)->Resource.Get(), sizeof(InstanceData));


    // Create keys
    std::vector<float> keys;
    keys.resize(instances.size());

    m_tetKeys = bm->CreateBuffer(device, cq, keys);
    bm->GetInstanceBuffer(m_tetKeys)->Resource.Get()->SetName(L"Tetrahedron Keys");
    m_tetKeysUAV = gmm->CreateBufferUAV(device, bm->GetInstanceBuffer(m_tetKeys)->Resource.Get(), sizeof(float));

    // Create payload
    // These are indices into the main StructuredBuffer
    std::vector<uint32_t> payload;
    for (uint32_t i = 0; i < instances.size(); i++)
    {
        payload.push_back(i);
    }

    m_tetIndices = bm->CreateBuffer(device, cq, payload);
    bm->GetInstanceBuffer(m_tetIndices)->Resource.Get()->SetName(L"Tetrahedron Indices");
    m_tetIndicesUAV = gmm->CreateBufferUAV(device, bm->GetInstanceBuffer(m_tetIndices)->Resource.Get(), sizeof(float));
}

void Game::CleanupResources()
{
    m_floor.reset();
    m_effect.reset();
    m_renderTarget.reset();

    ThrowIfFfxFailed(ffxParallelSortContextDestroy(&m_parallelSortContext));

    Gradient::BufferManager::Shutdown();
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
