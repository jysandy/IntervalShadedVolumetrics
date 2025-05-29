#pragma once

#include "pch.h"

#include <set>
#include <unordered_map>
#include <directxtk12/DescriptorHeap.h>
#include <directxtk12/DirectXHelpers.h>

namespace Gradient
{
    // Manages resources and descriptors. Not currently thread-safe.
    class GraphicsMemoryManager
    {
    public:
        using DescriptorIndex = DirectX::DescriptorPile::IndexType;

        enum class DescriptorIndexType
        {
            SRVorUAV, RTV, DSV
        };

        class DescriptorIndexContainer
        {
        public:
            DescriptorIndexContainer(DescriptorIndex index, DescriptorIndexType indexType);
            DescriptorIndexContainer(const DescriptorIndexContainer&) = delete;
            DescriptorIndexContainer(const DescriptorIndexContainer&&) = delete;

            D3D12_CPU_DESCRIPTOR_HANDLE GetCPUHandle();
            D3D12_GPU_DESCRIPTOR_HANDLE GetGPUHandle();

            ~DescriptorIndexContainer();

            DescriptorIndex m_index;
            DescriptorIndexType m_indexType;
        };

        using DescriptorView = std::shared_ptr<DescriptorIndexContainer>;


        static void Initialize(ID3D12Device* device);
        static void Shutdown();

        static GraphicsMemoryManager* Get();

        template <typename T>
        inline D3D12_GPU_VIRTUAL_ADDRESS AllocateConstant(const T& data);

        void Commit(ID3D12CommandQueue* cq);


        // SRV & UAV

        DescriptorIndex AllocateSrvOrUav();
        void FreeSrvOrUav(DescriptorIndex index);
        // Used by ImGui
        void FreeSrvByCpuHandle(D3D12_CPU_DESCRIPTOR_HANDLE cpuHandle);

        DescriptorView CreateSRV(
            ID3D12Device* device,
            ID3D12Resource* resource,
            bool isCubeMap = false
        );

        DescriptorView CreateSRV(
            ID3D12Device* device,
            ID3D12Resource* resource,
            D3D12_SHADER_RESOURCE_VIEW_DESC* srvDesc
        );

        DescriptorView CreateUAV(
            ID3D12Device* device,
            ID3D12Resource* resource,
            uint32_t mipLevel = 0
        );

        D3D12_CPU_DESCRIPTOR_HANDLE GetSRVOrUAVCpuHandle(DescriptorIndex index);
        D3D12_GPU_DESCRIPTOR_HANDLE GetSRVOrUAVGpuHandle(DescriptorIndex index);

        ID3D12DescriptorHeap* GetSrvUavDescriptorHeap();


        // RTV

        DescriptorIndex AllocateRTV();
        void FreeRTV(DescriptorIndex index);

        DescriptorView CreateRTV(
            ID3D12Device* device,
            ID3D12Resource* resource
        );

        DescriptorView CreateRTV(
            ID3D12Device* device,
            D3D12_RENDER_TARGET_VIEW_DESC desc,
            ID3D12Resource* resource
        );

        D3D12_CPU_DESCRIPTOR_HANDLE GetRTVCpuHandle(DescriptorIndex index);


        // DSV

        DescriptorIndex AllocateDSV();
        void FreeDSV(DescriptorIndex index);

        DescriptorView CreateDSV(
            ID3D12Device* device,
            ID3D12Resource* resource,
            D3D12_DEPTH_STENCIL_VIEW_DESC dsvDesc
        );

        D3D12_CPU_DESCRIPTOR_HANDLE GetDSVCpuHandle(DescriptorIndex index);

    private:
        GraphicsMemoryManager(ID3D12Device* device);
        void TrackCpuDescriptorHandle(DescriptorIndex index);
        void UntrackCpuDescriptorHandle(DescriptorIndex index);

        static std::unique_ptr<GraphicsMemoryManager> s_instance;

        std::unique_ptr<DirectX::GraphicsMemory> m_graphicsMemory;
        std::unique_ptr<DirectX::DescriptorPile> m_srvDescriptors;
        std::unique_ptr<DirectX::DescriptorPile> m_rtvDescriptors;
        std::unique_ptr<DirectX::DescriptorPile> m_dsvDescriptors;

        std::set<DescriptorIndex> m_freeSrvIndices;
        std::set<DescriptorIndex> m_freeRTVIndices;
        std::set<DescriptorIndex> m_freeDSVIndices;

        std::vector<DirectX::GraphicsResource> m_frameGraphicsResources;

        struct DescriptorHandleHash
        {
            std::size_t operator()(const D3D12_CPU_DESCRIPTOR_HANDLE& h) const noexcept
            {
                return std::hash<SIZE_T>{}(h.ptr);
            }
        };

        struct DescriptorHandleEqual
        {
            constexpr bool operator()(const D3D12_CPU_DESCRIPTOR_HANDLE& l,
                const D3D12_CPU_DESCRIPTOR_HANDLE& r) const
            {
                return l.ptr == r.ptr;
            }
        };

        std::unordered_map<D3D12_CPU_DESCRIPTOR_HANDLE,
            DescriptorIndex,
            DescriptorHandleHash,
            DescriptorHandleEqual>
            m_cpuHandleToSrvIndex;
    };

    template <typename T>
    inline D3D12_GPU_VIRTUAL_ADDRESS GraphicsMemoryManager::AllocateConstant(const T& data)
    {
        m_frameGraphicsResources.push_back(m_graphicsMemory->AllocateConstant(data));
        return m_frameGraphicsResources.back().GpuAddress();
    }
}