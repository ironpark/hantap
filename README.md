<img src="assets/icon.png" width="128" alt="">

# hantap

CapsLock 한/영 전환을 macOS 기본 기능 대신 처리하는 상주 에이전트입니다. 두 가지 문제를 겨냥합니다.

- **기기마다 다른 전환 지연**: macOS 기본 CapsLock 전환은 탭과 홀드를 구분하려고 일부러 기다리고, 그 지연이 키보드와 펌웨어마다 다릅니다. hantap은 HID 단계에서 CapsLock을 F18로 바꾸고(`hidutil`), 키를 누르는 순간 전환합니다.
- **비네이티브 앱에서 전환이 안 먹힘**: 기본 전환은 시스템 전체 입력 소스를 먼저 바꾸고 나서 앱에 알립니다. 이 순서 때문에 Electron, Java 같은 앱의 입력란은 포커스가 바뀔 때까지 이전 입력기에 머무를 수 있습니다. hantap은 입력 메뉴가 하는 것처럼, 키보드 포커스를 가진 앱의 TSM 포트에 직접 동기식으로 전환을 요청합니다([macism](https://github.com/laishulu/macism)의 방법).

## 동작

| 입력 | 결과 |
|---|---|
| CapsLock 탭 | 한글 ↔ 영문 (키를 누르는 순간) |
| CapsLock 500ms 이상 홀드 | 전환을 되돌리고 CapsLock 켜기/끄기 |
| Shift + CapsLock | CapsLock 켜기/끄기 |

- 전환이 끝날 때까지 이벤트 탭이 다음 키 입력을 잡아 둡니다. 그래서 CapsLock 직후에 친 글자도 새 입력기로 들어갑니다.
- 앱에 직접 요청할 수 없을 때만 대체 수단을 씁니다. `TISSelectInputSource`로 전환한 뒤, 앱을 활성화하지 않는 패널로 키 포커스를 잠깐(60ms) 가져갔다 돌려줍니다.
- 모든 전환은 로그에 경로, 걸린 시간, 대상 앱과 함께 기록됩니다.

## 설치

```sh
zsh scripts/install.sh
```

설치 후 **시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용**에서 hantap을 허용합니다. 묻는 경우 **입력 모니터링**도 허용합니다. 권한을 받기 전까지 CapsLock은 원래 동작을 그대로 유지합니다.

옵션은 install.sh 뒤에 붙이면 LaunchAgent에 들어갑니다.

```sh
zsh scripts/install.sh --hold-ms 0 --fallback activate
```

로그는 이렇게 봅니다.

```sh
tail -f ~/Library/Logs/hantap.log
```

로그 형식은 다음과 같습니다.

```
capslock -> com.apple.keylayout.ABC via tsm switch=0.9ms key->done=3.1ms app=com.microsoft.VSCode
```

- `switch`: 앱에 요청을 보내고 응답을 받기까지 걸린 시간
- `key->done`: 키보드 이벤트 시각부터 전환이 끝날 때까지 걸린 시간
- `via tis (...)`: 대체 수단을 썼다는 뜻이고, 괄호 안이 그 이유

## 제거

```sh
zsh scripts/uninstall.sh
```

## 단독 명령

```sh
hantap list            # 켜져 있는 입력 소스
hantap current
hantap switch ko|en|ID # 한 번 전환 (에이전트와 같은 경로)
hantap toggle
hantap restore-keys    # 에이전트가 비정상 종료돼 CapsLock이 안 먹힐 때
```

## 알려진 한계

- 비공개 API(`CPSGetKeyFocusProcess`, `CFMessagePortCreatePerProcessRemote`, `_CreateFlattenedInputSource`)를 씁니다. macOS 업데이트로 사라지면 대체 수단으로 동작하고, 로그에 경고가 남습니다.
- 임시 서명(ad-hoc)이라서 다시 빌드하고 설치할 때마다 손쉬운 사용 권한을 다시 줘야 할 수 있습니다. 목록에서 지우고 다시 추가하면 됩니다.
- 암호 입력란처럼 보안 입력이 켜진 상태에서는 이벤트 탭이 키를 받지 못해서, CapsLock이 F18로만 전달되고 전환되지 않을 수 있습니다.
- 에이전트가 강제 종료(SIGKILL)되면 CapsLock→F18 매핑이 남습니다. launchd가 곧 다시 띄우고, 직접 풀려면 `hantap restore-keys`를 실행합니다.
