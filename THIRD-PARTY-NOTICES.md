# Third-Party Notices

本项目衍生自以下作品。该作品由其版权人拥有，并按其原始许可证条款授权，
**不受本仓库根目录 `LICENSE` 的约束**。

---

## DZMeBookRead

本库的阅读器内核**衍生自** DZMeBookRead：排版分页、翻页与滚动、阅读菜单、目录与书签、
阅读记录归档等核心实现均以其为基础，经重构、重命名、模块化与功能调整而成。

- 作者：dengzemiao
- 项目主页：https://github.com/dengzemiao/DZMeBookRead
- 许可证：MIT

```
MIT License

Copyright (c) 2018 dengzemiao

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
---

## Readium swift-toolkit

朗读能力的**合成状态机**（`Sources/ReaderKit/Speech/ReaderSystemSpeechSynthesizer.swift`）
衍生自 Readium swift-toolkit 的 `AVTTSEngine`：显式状态机（idle / speaking / paused /
stopping）与「上一条 utterance 的回调未到达前不得提交下一条」这一约束取自该实现，
用于规避 `AVSpeechSynthesizer` 在 iOS 15 上的引擎死锁。

音色筛选规则（`ReaderSpeechVoiceCatalog`）中「过滤 `.eloquence.` 与
`com.apple.speech.synthesis.voice.` 前缀的老式音色」亦来自其 `TTSVoice` 实现。

本库的编排层（分句、翻页跟随、章节衔接、高亮）为自研，未使用其
`PublicationSpeechSynthesizer`。

- 项目主页：https://github.com/readium/swift-toolkit
- 许可证：BSD-3-Clause

```
Copyright 2024 Readium Foundation. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
