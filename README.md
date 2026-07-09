# 맥북 딕테이션 → 노션 다이렉트 전송 툴

⌘⇧D 한 번이면 어디서든 마이크가 켜지고, 말한 내용이 온디바이스 음성 인식으로 텍스트가 되어 **노션 데이터베이스에 바로 기록**됩니다. macOS 메뉴바 상주 앱(Swift 네이티브)이며, 외부 STT API 비용·지연이 없습니다.

> PRD 옵션 **C(Swift 메뉴바 앱) + 노션 API 직접 연동** 구현체입니다.

---

## 1. 동작 방식

| 단계 | 내용 |
|------|------|
| 트리거 | 전역 단축키 **⌘⇧D** (어떤 앱에서든) |
| 음성 → 텍스트 | macOS **Speech 프레임워크 온디바이스 인식** (Dictation과 동일 엔진, 무료·오프라인) |
| 종료 | **⌘⇧D 다시 입력** → 인식 종료 후 자동 전송 |
| 전송 | 노션 REST API `POST /v1/pages` 로 새 페이지 생성 (제목에 `음성 메모:` 말머리) |
| 피드백 | 메뉴바 아이콘 상태 변화 + 네이티브 알림(성공/실패) |
| 예외 | 오프라인이면 로컬 캐싱 → 네트워크 복구 시 자동 재전송 |

메뉴바 아이콘: 🎙 대기 · 🔴 녹음 중 · ⬆️ 전송 중 · ⚠️ 설정 필요

---

## 2. 사전 준비 (Prerequisites)

- **macOS 13(Ventura) 이상**
- **Xcode Command Line Tools** (Swift 툴체인 포함)
  ```bash
  xcode-select --install
  ```
- 한국어 받아쓰기 준비: **시스템 설정 › 키보드 › 받아쓰기**에서 언어에 **한국어**를 추가(최초 1회 다운로드). 온디바이스 인식에 필요합니다.

> 이 프로젝트는 Windows에서 작성되었지만, 빌드·실행은 **맥북에서** 이뤄집니다. 폴더 전체를 맥북으로 복사한 뒤 진행하세요.

---

## 3. 노션 준비 (5분)

1. **통합(Integration) 생성** → https://www.notion.so/my-integrations 접속 → `New integration`
   - 유형: **Internal**, 워크스페이스 선택
   - 생성 후 **Internal Integration Secret**(`secret_...` 또는 `ntn_...`)을 복사 → `notionToken`
2. **데이터베이스 준비 & 연결**
   - 기록할 노션 데이터베이스(표 형태)를 하나 준비합니다. 텍스트가 들어갈 **제목(Title) 속성 이름**을 확인하세요(기본값 `Name`, 한글이면 예: `이름`).
   - 데이터베이스 페이지 우측 상단 `···` › **Connections(연결)** › 위에서 만든 통합을 추가합니다. (이 단계를 빠뜨리면 403/객체 미발견 오류가 납니다.)
3. **Database ID 확보**
   - 데이터베이스를 브라우저에서 열면 URL이 이렇게 생겼습니다:
     `https://www.notion.so/<워크스페이스>/<32자리 DATABASE_ID>?v=...`
   - 이 **32자리**(하이픈 없는) 값이 `databaseId` 입니다.

---

## 4. 설정 파일 작성

앱을 처음 실행하면 다음 위치에 템플릿이 자동 생성됩니다(메뉴 › **설정 파일 열기**로도 열림):

```
~/Library/Application Support/MacDictationNotion/config.json
```

`config.example.json` 을 참고해 채워 넣으세요:

```json
{
  "notionToken": "secret_실제토큰",
  "databaseId": "32자리데이터베이스ID",
  "titleProperty": "Name",
  "locale": "ko-KR",
  "notePrefix": "음성 메모:",
  "notionVersion": "2022-06-28"
}
```

| 키 | 설명 | 기본값 |
|----|------|--------|
| `notionToken` | 통합 시크릿 (**필수**) | — |
| `databaseId` | 대상 DB ID (**필수**) | — |
| `titleProperty` | 제목 속성 이름 (DB와 일치해야 함) | `Name` |
| `locale` | 인식 언어 | `ko-KR` |
| `notePrefix` | 제목 말머리(딕테이션 교정용). 비우려면 `""` | `음성 메모:` |
| `notionVersion` | Notion API 버전 헤더 | `2022-06-28` |

> 토큰을 파일에 두기 싫다면 환경변수 `NOTION_TOKEN`, `NOTION_DATABASE_ID` 로 대체할 수 있습니다(파일 값보다 우선). `config.json` 은 `.gitignore` 처리되어 있습니다.

---

## 5. 빌드 & 실행

폴더에서:

```bash
chmod +x build.sh      # 최초 1회
./build.sh run         # 빌드 후 바로 실행
```

- `./build.sh` : `MacDictationNotion.app` 번들 생성 + ad-hoc 코드사인
- `open MacDictationNotion.app` : 실행 (Dock에는 안 뜨고 메뉴바에만 상주)
- 로그인 시 자동 실행하려면 **시스템 설정 › 일반 › 로그인 항목**에 이 `.app`을 추가하세요.

---

## 6. 권한 허용 (최초 1회)

첫 실행/첫 녹음 시 아래 권한 요청이 뜹니다. 모두 **허용**하세요:

- **마이크** (음성 입력)
- **음성 인식** (텍스트 변환)
- **알림** (전송 결과 표시)

거부했다면 **시스템 설정 › 개인정보 보호 및 보안**에서 각각 다시 켤 수 있습니다.

---

## 7. 사용법

1. 아이디어가 떠오르면 **⌘⇧D** — '띵' 소리와 함께 녹음 시작(아이콘 🔴)
2. 말하기: 예) *"AICC BPO 확장 관련 타깃 리스트 정리 필요"*
3. **⌘⇧D 다시** — 인식 종료 → 노션 전송(아이콘 ⬆️)
4. **"노션 전송 완료 ✅"** 알림 확인. DB에 `음성 메모: …` 제목의 새 행이 생깁니다.

---

## 8. 예외 처리 동작

- **오프라인/서버 오류(5xx·429)**: 텍스트를 `pending.json`에 캐싱하고 *"오프라인 — 임시 저장됨"* 알림. 네트워크가 복구되면 **자동 재전송**(메뉴 › *지금 재전송*으로 수동 실행도 가능).
- **인증/요청 오류(4xx, 예: 잘못된 토큰)**: *"전송 실패 ❌"* 알림으로 원인(HTTP 코드/메시지)을 표시. 큐를 막지 않도록 재시도 대상에서 제외됩니다.
- **딕테이션 인식 뭉개짐**: 제목에 `음성 메모:` 말머리가 붙어 나중에 교정 시 쉽게 식별됩니다.

---

## 9. 프로젝트 구조

```
MacDictationNotion/
├── Package.swift                 # SPM 실행 타깃 (macOS 13+)
├── build.sh                      # .app 번들 빌드 + ad-hoc 사인
├── config.example.json           # 설정 템플릿
├── Resources/Info.plist          # LSUIElement(메뉴바 전용) + 권한 설명
└── Sources/MacDictationNotion/
    ├── main.swift                # NSApplication 부트스트랩(.accessory)
    ├── AppDelegate.swift         # 상태머신·메뉴바·전송 조율
    ├── HotKeyManager.swift       # Carbon 전역 단축키 ⌘⇧D
    ├── SpeechRecognizer.swift    # 온디바이스 음성 인식
    ├── NotionClient.swift        # 노션 API 호출
    ├── OfflineQueue.swift        # 오프라인 캐싱/재전송 큐
    ├── Notifier.swift            # 네이티브 알림(+osascript 폴백)
    └── Settings.swift            # config.json 로딩
```

---

## 10. 트러블슈팅

| 증상 | 해결 |
|------|------|
| `swift: command not found` | `xcode-select --install` 후 재시도 |
| 전송 실패 **HTTP 401** | 토큰 오타/만료 — 통합 시크릿 재확인 |
| 전송 실패 **HTTP 404 / object not found** | DB에 통합을 **Connections로 연결**했는지, `databaseId` 32자리 정확한지 확인 |
| 전송 실패 **HTTP 400 (validation)** | `titleProperty` 이름이 실제 DB 제목 속성과 다름 |
| 녹음이 안 됨 | 마이크·음성 인식 권한, 그리고 받아쓰기 **한국어 언어 다운로드** 확인 |
| 단축키 무반응 | 다른 앱이 ⌘⇧D를 선점 중일 수 있음 — 앱 종료 후 재실행하거나 `HotKeyManager.register`의 keyCode 변경 |
| 알림이 안 뜸 | 시스템 설정 › 알림에서 이 앱 허용. (미허용 시 자동으로 osascript 알림으로 대체) |

---

## 11. 확장 아이디어

- 전송 전 LLM으로 요약/정제 후 노션에 저장
- 제목/본문 분리, 태그·카테고리 속성 자동 채우기
- 단축키를 설정 파일에서 지정 가능하게(현재는 코드 상수 ⌘⇧D)
