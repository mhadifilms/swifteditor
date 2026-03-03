#include <metal_stdlib>
using namespace metal;

// ─── Histogram ──────────────────────────────────────────────────────────────

/// Phase 1+2: Accumulate per-pixel R/G/B/Luma into 256-bin histograms.
/// Uses threadgroup-local atomics merged into global buffers.
kernel void histogramKernel(
    texture2d<half, access::read> inputTexture [[texture(0)]],
    device atomic_uint *globalHistR    [[buffer(0)]],
    device atomic_uint *globalHistG    [[buffer(1)]],
    device atomic_uint *globalHistB    [[buffer(2)]],
    device atomic_uint *globalHistLuma [[buffer(3)]],
    threadgroup atomic_uint *localHistR    [[threadgroup(0)]],
    threadgroup atomic_uint *localHistG    [[threadgroup(1)]],
    threadgroup atomic_uint *localHistB    [[threadgroup(2)]],
    threadgroup atomic_uint *localHistLuma [[threadgroup(3)]],
    uint2 gid [[thread_position_in_grid]],
    uint  tid [[thread_index_in_threadgroup]],
    uint2 tgSize [[threads_per_threadgroup]]
) {
    uint threadsPerGroup = tgSize.x * tgSize.y;
    for (uint i = tid; i < 256; i += threadsPerGroup) {
        atomic_store_explicit(&localHistR[i],    0, memory_order_relaxed);
        atomic_store_explicit(&localHistG[i],    0, memory_order_relaxed);
        atomic_store_explicit(&localHistB[i],    0, memory_order_relaxed);
        atomic_store_explicit(&localHistLuma[i], 0, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        // Still need to participate in the merge barrier below.
        threadgroup_barrier(mem_flags::mem_threadgroup);
        for (uint i = tid; i < 256; i += threadsPerGroup) {
            uint v;
            v = atomic_load_explicit(&localHistR[i], memory_order_relaxed);
            if (v > 0) atomic_fetch_add_explicit(&globalHistR[i], v, memory_order_relaxed);
            v = atomic_load_explicit(&localHistG[i], memory_order_relaxed);
            if (v > 0) atomic_fetch_add_explicit(&globalHistG[i], v, memory_order_relaxed);
            v = atomic_load_explicit(&localHistB[i], memory_order_relaxed);
            if (v > 0) atomic_fetch_add_explicit(&globalHistB[i], v, memory_order_relaxed);
            v = atomic_load_explicit(&localHistLuma[i], memory_order_relaxed);
            if (v > 0) atomic_fetch_add_explicit(&globalHistLuma[i], v, memory_order_relaxed);
        }
        return;
    }

    half4 color = inputTexture.read(gid);
    uint binR = uint(clamp(color.r, 0.0h, 1.0h) * 255.0h);
    uint binG = uint(clamp(color.g, 0.0h, 1.0h) * 255.0h);
    uint binB = uint(clamp(color.b, 0.0h, 1.0h) * 255.0h);
    half luma = dot(color.rgb, half3(0.2126h, 0.7152h, 0.0722h));
    uint binLuma = uint(clamp(luma, 0.0h, 1.0h) * 255.0h);

    atomic_fetch_add_explicit(&localHistR[binR],       1, memory_order_relaxed);
    atomic_fetch_add_explicit(&localHistG[binG],       1, memory_order_relaxed);
    atomic_fetch_add_explicit(&localHistB[binB],       1, memory_order_relaxed);
    atomic_fetch_add_explicit(&localHistLuma[binLuma], 1, memory_order_relaxed);

    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Merge local into global
    for (uint i = tid; i < 256; i += threadsPerGroup) {
        uint v;
        v = atomic_load_explicit(&localHistR[i], memory_order_relaxed);
        if (v > 0) atomic_fetch_add_explicit(&globalHistR[i], v, memory_order_relaxed);
        v = atomic_load_explicit(&localHistG[i], memory_order_relaxed);
        if (v > 0) atomic_fetch_add_explicit(&globalHistG[i], v, memory_order_relaxed);
        v = atomic_load_explicit(&localHistB[i], memory_order_relaxed);
        if (v > 0) atomic_fetch_add_explicit(&globalHistB[i], v, memory_order_relaxed);
        v = atomic_load_explicit(&localHistLuma[i], memory_order_relaxed);
        if (v > 0) atomic_fetch_add_explicit(&globalHistLuma[i], v, memory_order_relaxed);
    }
}

/// Render histogram bins as vertical bars into an output texture.
kernel void histogramVisualizeKernel(
    device uint *histR    [[buffer(0)]],
    device uint *histG    [[buffer(1)]],
    device uint *histB    [[buffer(2)]],
    device uint *histLuma [[buffer(3)]],
    texture2d<half, access::write> outputTexture [[texture(0)]],
    constant uint &maxCount    [[buffer(4)]],
    constant float &brightness [[buffer(5)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width  = outputTexture.get_width();
    uint height = outputTexture.get_height();
    if (gid.x >= width || gid.y >= height) return;

    uint bin = gid.x * 256 / width;
    float pixelY = 1.0 - float(gid.y) / float(height); // bottom = 0

    float normR = float(histR[bin])    / float(maxCount);
    float normG = float(histG[bin])    / float(maxCount);
    float normB = float(histB[bin])    / float(maxCount);
    float normL = float(histLuma[bin]) / float(maxCount);

    half4 color = half4(0.05h, 0.05h, 0.05h, 1.0h);
    if (pixelY <= normL * brightness) {
        color = half4(0.6h, 0.6h, 0.6h, 1.0h);
    }
    if (pixelY <= normR * brightness) {
        color.r = max(color.r, 0.85h);
    }
    if (pixelY <= normG * brightness) {
        color.g = max(color.g, 0.85h);
    }
    if (pixelY <= normB * brightness) {
        color.b = max(color.b, 0.85h);
    }

    outputTexture.write(color, gid);
}

// ─── Waveform ───────────────────────────────────────────────────────────────

/// Accumulate luma values per column.
kernel void waveformKernel(
    texture2d<half, access::read> inputTexture [[texture(0)]],
    device atomic_uint *waveformData [[buffer(0)]],   // [scopeWidth * 256]
    constant uint &scopeWidth [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint imgW = inputTexture.get_width();
    uint imgH = inputTexture.get_height();
    if (gid.x >= imgW || gid.y >= imgH) return;

    half4 color = inputTexture.read(gid);
    half luma = dot(color.rgb, half3(0.2126h, 0.7152h, 0.0722h));
    uint lumaBin = uint(clamp(luma, 0.0h, 1.0h) * 255.0h);
    uint col = gid.x * scopeWidth / imgW;
    uint index = col * 256 + lumaBin;
    atomic_fetch_add_explicit(&waveformData[index], 1, memory_order_relaxed);
}

/// Visualize accumulated waveform data.
kernel void waveformVisualizeKernel(
    device uint *waveformData [[buffer(0)]],
    texture2d<half, access::write> outputTexture [[texture(0)]],
    constant uint &scopeWidth  [[buffer(1)]],
    constant uint &maxCount    [[buffer(2)]],
    constant float &brightness [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width  = outputTexture.get_width();
    uint height = outputTexture.get_height();
    if (gid.x >= width || gid.y >= height) return;

    uint col     = gid.x * scopeWidth / width;
    uint lumaBin = (height - 1 - gid.y) * 256 / height;
    uint count   = waveformData[col * 256 + lumaBin];

    if (count > 0) {
        float intensity = clamp(log2(float(count) + 1.0) / log2(float(maxCount) + 1.0) * brightness, 0.0, 1.0);
        outputTexture.write(half4(intensity * 0.3h, intensity * 1.0h, intensity * 0.3h, 1.0h), gid);
    } else {
        outputTexture.write(half4(0.02h, 0.02h, 0.02h, 1.0h), gid);
    }
}

// ─── RGB Parade ─────────────────────────────────────────────────────────────

/// Accumulate R, G, B channel values per column into separate buffers.
kernel void rgbParadeKernel(
    texture2d<half, access::read> inputTexture [[texture(0)]],
    device atomic_uint *paradeR [[buffer(0)]],   // [paradeWidth * 256]
    device atomic_uint *paradeG [[buffer(1)]],
    device atomic_uint *paradeB [[buffer(2)]],
    constant uint &paradeWidth [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint imgW = inputTexture.get_width();
    uint imgH = inputTexture.get_height();
    if (gid.x >= imgW || gid.y >= imgH) return;

    half4 color = inputTexture.read(gid);
    uint binR = uint(clamp(color.r, 0.0h, 1.0h) * 255.0h);
    uint binG = uint(clamp(color.g, 0.0h, 1.0h) * 255.0h);
    uint binB = uint(clamp(color.b, 0.0h, 1.0h) * 255.0h);
    uint col  = gid.x * paradeWidth / imgW;

    atomic_fetch_add_explicit(&paradeR[col * 256 + binR], 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&paradeG[col * 256 + binG], 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&paradeB[col * 256 + binB], 1, memory_order_relaxed);
}

/// Visualize RGB parade as three side-by-side waveforms.
kernel void rgbParadeVisualizeKernel(
    device uint *paradeR [[buffer(0)]],
    device uint *paradeG [[buffer(1)]],
    device uint *paradeB [[buffer(2)]],
    texture2d<half, access::write> outputTexture [[texture(0)]],
    constant uint &paradeWidth [[buffer(3)]],
    constant uint &maxCount    [[buffer(4)]],
    constant float &brightness [[buffer(5)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width  = outputTexture.get_width();
    uint height = outputTexture.get_height();
    if (gid.x >= width || gid.y >= height) return;

    uint thirdWidth   = width / 3;
    uint channelIndex = min(gid.x / thirdWidth, 2u);
    uint localX       = gid.x - channelIndex * thirdWidth;

    uint col      = localX * paradeWidth / thirdWidth;
    uint valueBin = (height - 1 - gid.y) * 256 / height;
    uint index    = col * 256 + valueBin;

    uint count = 0;
    half4 channelColor;
    if (channelIndex == 0) {
        count = paradeR[index];
        channelColor = half4(1.0h, 0.2h, 0.2h, 1.0h);
    } else if (channelIndex == 1) {
        count = paradeG[index];
        channelColor = half4(0.2h, 1.0h, 0.2h, 1.0h);
    } else {
        count = paradeB[index];
        channelColor = half4(0.2h, 0.2h, 1.0h, 1.0h);
    }

    if (count > 0) {
        float intensity = clamp(log2(float(count) + 1.0) / log2(float(maxCount) + 1.0) * brightness, 0.0, 1.0);
        outputTexture.write(channelColor * half(intensity), gid);
    } else {
        // Separator lines between channels
        if (gid.x == thirdWidth || gid.x == thirdWidth * 2) {
            outputTexture.write(half4(0.15h, 0.15h, 0.15h, 1.0h), gid);
        } else {
            outputTexture.write(half4(0.02h, 0.02h, 0.02h, 1.0h), gid);
        }
    }
}

// ─── Vectorscope ────────────────────────────────────────────────────────────

/// Accumulate Cb/Cr chrominance values into a 2D scatter grid.
kernel void vectorscopeKernel(
    texture2d<half, access::read> inputTexture [[texture(0)]],
    device atomic_uint *scopeData [[buffer(0)]],   // [scopeSize * scopeSize]
    constant uint &scopeSize [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint imgW = inputTexture.get_width();
    uint imgH = inputTexture.get_height();
    if (gid.x >= imgW || gid.y >= imgH) return;

    half4 color = inputTexture.read(gid);

    // RGB to YCbCr (BT.709)
    half Cb = -0.1146h * color.r - 0.3854h * color.g + 0.5000h * color.b;
    half Cr =  0.5000h * color.r - 0.4542h * color.g - 0.0458h * color.b;

    // Map Cb, Cr from (-0.5, 0.5) to (0, scopeSize-1)
    uint x = uint(clamp((Cb + 0.5h) * half(scopeSize), 0.0h, half(scopeSize - 1)));
    uint y = uint(clamp((0.5h - Cr) * half(scopeSize), 0.0h, half(scopeSize - 1)));

    atomic_fetch_add_explicit(&scopeData[y * scopeSize + x], 1, memory_order_relaxed);
}

/// Visualize vectorscope with circular boundary and optional skin tone line.
kernel void vectorscopeVisualizeKernel(
    device uint *scopeData [[buffer(0)]],
    texture2d<half, access::write> outputTexture [[texture(0)]],
    constant uint  &scopeSize      [[buffer(1)]],
    constant uint  &maxCount       [[buffer(2)]],
    constant float &brightness     [[buffer(3)]],
    constant uint  &showSkinTone   [[buffer(4)]],
    constant uint  &showGraticule  [[buffer(5)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width  = outputTexture.get_width();
    uint height = outputTexture.get_height();
    if (gid.x >= width || gid.y >= height) return;

    float2 center = float2(width / 2.0, height / 2.0);
    float2 pos    = float2(gid.x, gid.y);
    float  dist   = distance(pos, center);
    float  radius = float(min(width, height)) / 2.0;

    // Outside the circle
    if (dist > radius) {
        outputTexture.write(half4(0.0h, 0.0h, 0.0h, 1.0h), gid);
        return;
    }

    // Circle outline
    if (showGraticule != 0 && abs(dist - radius) < 1.5) {
        outputTexture.write(half4(0.3h, 0.3h, 0.3h, 1.0h), gid);
        return;
    }

    // Crosshair
    if (showGraticule != 0 &&
        (abs(float(gid.x) - center.x) < 0.5 || abs(float(gid.y) - center.y) < 0.5)) {
        outputTexture.write(half4(0.12h, 0.12h, 0.12h, 1.0h), gid);
        return;
    }

    // Skin tone line (approx 123 degrees from positive Cb axis in vectorscope)
    if (showSkinTone != 0 && showGraticule != 0) {
        float2 fromCenter = pos - center;
        float angle = atan2(-fromCenter.y, fromCenter.x);
        // Skin tone angle ~ 123 degrees (in radians ~2.147)
        float skinAngle = 2.147;
        if (abs(angle - skinAngle) < 0.015 && dist < radius) {
            outputTexture.write(half4(0.35h, 0.25h, 0.15h, 1.0h), gid);
            return;
        }
    }

    // Scope data
    uint scopeX = gid.x * scopeSize / width;
    uint scopeY = gid.y * scopeSize / height;
    uint count  = scopeData[scopeY * scopeSize + scopeX];

    if (count > 0) {
        float intensity = clamp(log2(float(count) + 1.0) / log2(float(maxCount) + 1.0) * brightness, 0.0, 1.0);

        // Color the dot based on its CbCr position
        float2 normalized = float2(gid.x, gid.y) / float2(width, height);
        float Cb = normalized.x - 0.5;
        float Cr = 0.5 - normalized.y;
        float3 hueColor = float3(
            clamp(0.5 + 1.402 * Cr, 0.0, 1.0),
            clamp(0.5 - 0.344 * Cb - 0.714 * Cr, 0.0, 1.0),
            clamp(0.5 + 1.772 * Cb, 0.0, 1.0)
        );

        outputTexture.write(half4(half3(hueColor) * half(intensity), 1.0h), gid);
    } else {
        outputTexture.write(half4(0.02h, 0.02h, 0.02h, 1.0h), gid);
    }
}
