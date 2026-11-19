import Foundation

// Pure-Swift Argon2id (RFC 9106, version 0x13) and BLAKE2b, translated from the
// PHC winner reference implementation. Vendored so backups restore with exactly
// the same passphrase as the Flutter app, without an external dependency.

private let blakeIV: [UInt64] = [
    0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
    0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
]

private let sigma: [[Int]] = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
    [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
    [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
    [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
    [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
    [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
    [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
    [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
    [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
]

@inline(__always) private func rotr64(_ x: UInt64, _ n: UInt64) -> UInt64 {
    (x >> n) | (x << (64 - n))
}

@inline(__always) private func le32(_ value: UInt32) -> [UInt8] {
    (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
}

@inline(__always) private func le64(_ value: UInt64) -> [UInt8] {
    (0..<8).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
}

private func load64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
    var value: UInt64 = 0
    for i in 0..<8 { value |= UInt64(bytes[offset + i]) << (8 * i) }
    return value
}

private func blake2bCompress(h: inout [UInt64], m: [UInt64], counter: UInt64, finalBlock: UInt64) {
    var v = h + blakeIV
    v[12] ^= counter
    v[13] ^= 0 // high counter word; Lifelog never hashes more than 2^64 bytes
    v[14] ^= finalBlock

    @inline(__always) func g(_ a: UInt64, _ b: UInt64, _ c: UInt64, _ d: UInt64,
                             _ x: UInt64, _ y: UInt64) -> (UInt64, UInt64, UInt64, UInt64) {
        var a = a, b = b, c = c, d = d
        a = a &+ b &+ x
        d = rotr64(d ^ a, 32)
        c = c &+ d
        b = rotr64(b ^ c, 24)
        a = a &+ b &+ y
        d = rotr64(d ^ a, 16)
        c = c &+ d
        b = rotr64(b ^ c, 63)
        return (a, b, c, d)
    }

    for r in 0..<12 {
        let s = sigma[r]
        let r0 = g(v[0], v[4], v[8], v[12], m[s[0]], m[s[1]])
        v[0] = r0.0; v[4] = r0.1; v[8] = r0.2; v[12] = r0.3
        let r1 = g(v[1], v[5], v[9], v[13], m[s[2]], m[s[3]])
        v[1] = r1.0; v[5] = r1.1; v[9] = r1.2; v[13] = r1.3
        let r2 = g(v[2], v[6], v[10], v[14], m[s[4]], m[s[5]])
        v[2] = r2.0; v[6] = r2.1; v[10] = r2.2; v[14] = r2.3
        let r3 = g(v[3], v[7], v[11], v[15], m[s[6]], m[s[7]])
        v[3] = r3.0; v[7] = r3.1; v[11] = r3.2; v[15] = r3.3
        let r4 = g(v[0], v[5], v[10], v[15], m[s[8]], m[s[9]])
        v[0] = r4.0; v[5] = r4.1; v[10] = r4.2; v[15] = r4.3
        let r5 = g(v[1], v[6], v[11], v[12], m[s[10]], m[s[11]])
        v[1] = r5.0; v[6] = r5.1; v[11] = r5.2; v[12] = r5.3
        let r6 = g(v[2], v[7], v[8], v[13], m[s[12]], m[s[13]])
        v[2] = r6.0; v[7] = r6.1; v[8] = r6.2; v[13] = r6.3
        let r7 = g(v[3], v[4], v[9], v[14], m[s[14]], m[s[15]])
        v[3] = r7.0; v[4] = r7.1; v[9] = r7.2; v[14] = r7.3
    }
    for i in 0..<8 { h[i] ^= v[i] ^ v[i + 8] }
}

private func blake2b(_ input: [UInt8], outLength: Int) -> [UInt8] {
    var h = blakeIV
    h[0] ^= UInt64(0x01010000) ^ UInt64(outLength)
    var counter: UInt64 = 0
    var offset = 0
    while input.count - offset > 128 {
        let block = (0..<16).map { load64(input, offset + $0 * 8) }
        blake2bCompress(h: &h, m: block, counter: counter + 128, finalBlock: 0)
        counter += 128
        offset += 128
    }
    let remaining = input.count - offset
    var last = [UInt8](repeating: 0, count: 128)
    for i in 0..<remaining { last[i] = input[offset + i] }
    blake2bCompress(h: &h, m: (0..<16).map { load64(last, $0 * 8) },
                    counter: counter + UInt64(remaining), finalBlock: UInt64.max)
    let digest = h.flatMap(le64)
    return Array(digest.prefix(outLength))
}

/// Argon2's variable-length BLAKE2b hash (blake2b_long in the reference code).
private func blake2bLong(_ input: [UInt8], outLength: Int) -> [UInt8] {
    let prefixed = le32(UInt32(outLength)) + input
    if outLength <= 64 { return blake2b(prefixed, outLength: outLength) }
    var output: [UInt8] = []
    var buffer = blake2b(prefixed, outLength: 64)
    output.append(contentsOf: buffer.prefix(32))
    var toProduce = outLength - 32
    while toProduce > 64 {
        buffer = blake2b(buffer, outLength: 64)
        output.append(contentsOf: buffer.prefix(32))
        toProduce -= 32
    }
    buffer = blake2b(buffer, outLength: toProduce)
    output.append(contentsOf: buffer)
    return output
}

private struct ArgonBlock {
    var v = [UInt64](repeating: 0, count: 128)

    static func from(bytes: [UInt8]) -> ArgonBlock {
        var block = ArgonBlock()
        for i in 0..<128 { block.v[i] = load64(bytes, i * 8) }
        return block
    }

    var bytes: [UInt8] { v.flatMap(le64) }
}

@inline(__always) private func fBlaMka(_ x: UInt64, _ y: UInt64) -> UInt64 {
    let mask: UInt64 = 0xFFFFFFFF
    let xy = (x & mask) &* (y & mask)
    return x &+ y &+ 2 &* xy
}

private func blakeRound(_ block: inout ArgonBlock, _ index: [Int]) {
    var w = [UInt64](repeating: 0, count: 16)
    for j in 0..<16 { w[j] = block.v[index[j]] }

    func g(_ a: UInt64, _ b: UInt64, _ c: UInt64, _ d: UInt64) -> (UInt64, UInt64, UInt64, UInt64) {
        var a = a, b = b, c = c, d = d
        a = fBlaMka(a, b)
        d = rotr64(d ^ a, 32)
        c = fBlaMka(c, d)
        b = rotr64(b ^ c, 24)
        a = fBlaMka(a, b)
        d = rotr64(d ^ a, 16)
        c = fBlaMka(c, d)
        b = rotr64(b ^ c, 63)
        return (a, b, c, d)
    }

    let r0 = g(w[0], w[4], w[8], w[12])
    w[0] = r0.0; w[4] = r0.1; w[8] = r0.2; w[12] = r0.3
    let r1 = g(w[1], w[5], w[9], w[13])
    w[1] = r1.0; w[5] = r1.1; w[9] = r1.2; w[13] = r1.3
    let r2 = g(w[2], w[6], w[10], w[14])
    w[2] = r2.0; w[6] = r2.1; w[10] = r2.2; w[14] = r2.3
    let r3 = g(w[3], w[7], w[11], w[15])
    w[3] = r3.0; w[7] = r3.1; w[11] = r3.2; w[15] = r3.3
    let r4 = g(w[0], w[5], w[10], w[15])
    w[0] = r4.0; w[5] = r4.1; w[10] = r4.2; w[15] = r4.3
    let r5 = g(w[1], w[6], w[11], w[12])
    w[1] = r5.0; w[6] = r5.1; w[11] = r5.2; w[12] = r5.3
    let r6 = g(w[2], w[7], w[8], w[13])
    w[2] = r6.0; w[7] = r6.1; w[8] = r6.2; w[13] = r6.3
    let r7 = g(w[3], w[4], w[9], w[14])
    w[3] = r7.0; w[4] = r7.1; w[9] = r7.2; w[14] = r7.3
    for j in 0..<16 { block.v[index[j]] = w[j] }
}

private func fillBlock(prev: ArgonBlock, ref: ArgonBlock, next: inout ArgonBlock, withXor: Bool) {
    var blockR = ref
    for i in 0..<128 { blockR.v[i] ^= prev.v[i] }
    var temp = blockR
    if withXor {
        for i in 0..<128 { temp.v[i] ^= next.v[i] }
    }
    for i in 0..<8 {
        blakeRound(&blockR, (0..<16).map { 16 * i + $0 })
    }
    for i in 0..<8 {
        var indices: [Int] = []
        indices.reserveCapacity(16)
        for j in 0..<8 {
            let base = 2 * i + 16 * j
            indices.append(base)
            indices.append(base + 1)
        }
        blakeRound(&blockR, indices)
    }
    for i in 0..<128 { next.v[i] = temp.v[i] ^ blockR.v[i] }
}

enum Argon2id {
    /// Defaults match the Flutter `CryptoService.deriveBackupKey` exactly.
    static func hash(
        password: [UInt8],
        salt: [UInt8],
        memoryKiB: Int = 19456,
        iterations: Int = 2,
        parallelism: Int = 1,
        outputLength: Int = 32
    ) -> [UInt8] {
        let lanes = max(1, parallelism)
        let segmentLength = max(memoryKiB / (lanes * 4), 2)
        let memoryBlocks = segmentLength * lanes * 4
        let laneLength = segmentLength * 4

        // H0 = Blake2b(LE32(p) || LE32(tagLen) || LE32(m) || LE32(t) || LE32(v) ||
        //              LE32(type) || LE32(pwdLen) || P || LE32(saltLen) || S ||
        //              LE32(secretLen) || LE32(adLen))
        var params: [UInt8] = []
        params += le32(UInt32(lanes))
        params += le32(UInt32(outputLength))
        params += le32(UInt32(memoryKiB))
        params += le32(UInt32(iterations))
        params += le32(0x13) // version 1.3
        params += le32(2) // Argon2id
        params += le32(UInt32(password.count))
        params += password
        params += le32(UInt32(salt.count))
        params += salt
        params += le32(0)
        params += le32(0)
        let h0 = blake2b(params, outLength: 64)

        var memory = [ArgonBlock](repeating: ArgonBlock(), count: memoryBlocks)
        var seed = h0 + [UInt8](repeating: 0, count: 8)
        for lane in 0..<lanes {
            let base = lane * laneLength
            for blockIndex in 0..<2 {
                seed.replaceSubrange(64..<68, with: le32(UInt32(blockIndex)))
                seed.replaceSubrange(68..<72, with: le32(UInt32(lane)))
                memory[base + blockIndex] = ArgonBlock.from(bytes: blake2bLong(seed, outLength: 1024))
            }
        }

        for pass in 0..<iterations {
            for slice in 0..<4 {
                for lane in 0..<lanes {
                    fillSegment(
                        &memory, pass: pass, slice: slice, lane: lane,
                        lanes: lanes, segmentLength: segmentLength,
                        laneLength: laneLength, memoryBlocks: memoryBlocks,
                        iterations: iterations
                    )
                }
            }
        }

        var finalBlock = memory[laneLength - 1]
        for lane in 1..<lanes {
            let last = lane * laneLength + laneLength - 1
            for i in 0..<128 { finalBlock.v[i] ^= memory[last].v[i] }
        }
        return blake2bLong(finalBlock.bytes, outLength: outputLength)
    }

    private static func fillSegment(
        _ memory: inout [ArgonBlock],
        pass: Int, slice: Int, lane: Int,
        lanes: Int, segmentLength: Int, laneLength: Int,
        memoryBlocks: Int, iterations: Int
    ) {
        let dataIndependent = pass == 0 && slice < 2
        let startingIndex = (pass == 0 && slice == 0) ? 2 : 0
        var addressBlock = ArgonBlock()
        var inputBlock = ArgonBlock()
        let zeroBlock = ArgonBlock()
        var nextAddresses: (() -> Void)? = nil

        if dataIndependent {
            inputBlock.v[0] = UInt64(pass)
            inputBlock.v[1] = UInt64(lane)
            inputBlock.v[2] = UInt64(slice)
            inputBlock.v[3] = UInt64(memoryBlocks)
            inputBlock.v[4] = UInt64(iterations)
            inputBlock.v[5] = 2 // Argon2id
            nextAddresses = {
                inputBlock.v[6] += 1
                var first = ArgonBlock()
                fillBlock(prev: zeroBlock, ref: inputBlock, next: &first, withXor: false)
                var second = ArgonBlock()
                fillBlock(prev: zeroBlock, ref: first, next: &second, withXor: false)
                addressBlock = second
            }
            if startingIndex == 2 { nextAddresses?() }
        }

        var current = lane * laneLength + slice * segmentLength + startingIndex
        var previous = current % laneLength == 0 ? current + laneLength - 1 : current - 1

        for i in startingIndex..<segmentLength {
            if current % laneLength == 1 { previous = current - 1 }

            let pseudoRandom: UInt64
            if dataIndependent {
                if i % 128 == 0 { nextAddresses?() }
                pseudoRandom = addressBlock.v[i % 128]
            } else {
                pseudoRandom = memory[previous].v[0]
            }

            var referenceLane = Int((pseudoRandom >> 32) % UInt64(lanes))
            if pass == 0 && slice == 0 { referenceLane = lane }

            let referenceIndex = indexAlpha(
                pass: pass, slice: slice, index: i,
                pseudoRandom: UInt32(truncatingIfNeeded: pseudoRandom),
                sameLane: referenceLane == lane,
                segmentLength: segmentLength, laneLength: laneLength
            )
            let reference = referenceLane * laneLength + referenceIndex
            fillBlock(prev: memory[previous], ref: memory[reference],
                      next: &memory[current], withXor: pass > 0)
            current += 1
            previous += 1
        }
    }

    private static func indexAlpha(
        pass: Int, slice: Int, index: Int, pseudoRandom: UInt32, sameLane: Bool,
        segmentLength: Int, laneLength: Int
    ) -> Int {
        let area: Int
        if pass == 0 {
            if slice == 0 {
                area = index - 1
            } else if sameLane {
                area = slice * segmentLength + index - 1
            } else {
                area = slice * segmentLength + (index == 0 ? -1 : 0)
            }
        } else if sameLane {
            area = laneLength - segmentLength + index - 1
        } else {
            area = laneLength - segmentLength + (index == 0 ? -1 : 0)
        }

        var relative = UInt64(pseudoRandom)
        relative = (relative * relative) >> 32
        relative = UInt64(area - 1) - ((UInt64(area) * relative) >> 32)
        let start = pass == 0 ? 0 : (slice == 3 ? 0 : (slice + 1) * segmentLength)
        return Int((UInt64(start) + relative) % UInt64(laneLength))
    }
}
