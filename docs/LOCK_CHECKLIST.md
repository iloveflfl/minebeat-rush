# MineBeat Rush — [LOCK] 구현 체크리스트

GDD v1.0 §32.1 지시에 따라 [LOCK] 항목을 구현 체크리스트로 변환한 문서.
각 항목 옆의 파일/기호가 그 LOCK을 강제하는 지점이다.

## L1. High Concept (§1)
- [x] 무너지는 사막 초장대 석교, 지뢰찾기 숫자로 탈출 지뢰 탐색, GO에 밟아 폭발 추진, 유한 스테이지
  - `scripts/gameplay/GameDirector.gd` (전체 루프), `scripts/core/Stage1Data.gd` (authored 34섹터 + Sun Gate)

## L2. 장르 (§2)
- [x] 엔드리스 아님. 2.5~4분 authored stage, 시작/상승/피날레/도착 존재
  - `Stage1Data.gd::build()` → Act0..Finale, `GameDirector::_finish_stage()`

## L3. 세계 공간 (§5.1, §5.2)
- [x] 섹터는 로직 단위. 미술적으로 하나의 연속 석교 (교각/난간/파손 스팬/하부 통로/Sun Gate 원경)
  - `scripts/gameplay/BridgeManager.gd::_build_continuous_structure()`
- [x] 사고 전후 같은 맵. 순간이동 없음 — 인트로 갑판이 sector index -1 로 같은 월드에 존재
  - `BridgeManager::build_intro_deck()`

## L4. 시간 규칙 (§6)
- [x] 리듬은 대시를 제한하지 않는다. 플랫폼 수명/폭발 국면만 결정
  - `PlayerMotor::_unhandled_input()` 은 BeatConductor를 참조하지 않음 (강제 불변식)
- [x] 지상 4박 / 공중 4박, 정점은 공중 2박째 고정
  - `LaunchController::sample()` — 정점 시각 = 발사 + 2박 (템포 변화 구간에서도 유지)
- [x] 손상은 뒤에서 한 칸씩 삭제가 아니라 섹터 전체가 1→2→3 단계
  - `BridgeSector::set_damage()` — 섹터 루트 노드 전체에 settle/tilt 적용

## L5. 조작 (§7.1)
- [x] 대각선 대시 없음 — `PlayerMotor.MOVES` 에 L/F/R 3종만 존재
- [x] 대시는 박자 무관, 언제든 입력 가능
- [x] 코어 러닝 구간에 후진 입력 없음 (`PlayerMotor.allow_back` 은 Act0에서만 true)
- [x] 화면 기준 좌/우 == 입력. 카메라 yaw/roll 영구 0
  - `CameraDirector::_process()` — `rotation = Vector3(pitch, 0, 0)` 하드 고정
- [x] 타일 중심 → 타일 중심 authored grid movement, 관성으로 중심 이탈 없음
  - `PlayerMotor::_finish_dash()` — 도착 시 정확한 셀 중심 snap

## L6. 지뢰찾기 법칙 (§8)
- [x] 숫자 = 인접(8방) 지뢰 수. 스테이지 전체에서 불변
  - `MineGrid::number_at()` 단 하나의 구현. 숫자 표시는 전부 여기서 파생
  - 보드는 ASCII로 저작하지만 **숫자는 절대 손으로 적지 않는다.** 배치된 장약에서
    파생되므로 단서가 보드와 어긋날 수 없다 (`SectorData.pattern`)
- [x] 5열 확장은 새 규칙 없이 폭만 확장
- [x] 유일해 보장 / 50-50 금지 / 도달 가능성 자동 검증
  - `MineGrid::validate()` + `Stage1Data::_validate()` — 실패 시 기동 중단
  - 44섹터 × 모든 착지 열에 대해 매 빌드 재검증

## L6b. 난이도 상승축 (§18 [LOCK])
숫자의 의미는 바뀌지 않는다. 상승은 "몇 개의 단서를 결합해야 하는가"로 만든다.

- [x] `MineGrid::deduction_depth()` 가 실제 추론 단계 수를 측정한다
  (단일 단서 → 0/1 확정 → 부분집합 규칙). 테스트가 곡선을 강제한다.
- [x] 장약을 인접/적층 배치해 단서값이 2와 3에 도달
  (튜토리얼 이후 37섹터 중 26섹터가 2 이상, 최대 3)
- [x] 두 번째 미개봉 띠 — 아래 단서행으로 안전을 증명한 뒤에야 위 단서행이 읽힌다
- [x] §19 [TEST] "부분 단서 파손" — 무너진 석주가 단서 하나를 지운다.
  남은 단서만으로 유일해가 성립함을 솔버가 매 빌드 증명

## L7. 실패 처리 (§10.2)
- [x] 즉사 없음. GO에 지뢰 미도달 → 섹터와 함께 추락 → 머플러 활공으로 다음 구간 진행
  - `LaunchController::begin_glide()`, `GameDirector::_resolve_go()`
- [x] 잘못된 안전타일 → 그 타일이 열리며 실제 숫자가 드러남. WRONG 텍스트 없음
  - `BridgeSector::reveal_all_candidates()`

## L8. 판정 (§11.2)
- [x] PERFECT/GOOD/BAD가 수평거리·체공시간·착지 시각을 바꾸지 않음
  - `LaunchController::begin_launch()` 는 grade를 궤적 계산에 넣지 않음 (자세/VFX/음향만)

## L9. 온보딩 (§12)
- [x] 설명문 없음. 정답 번역 보조표식 없음
  - HUD에 정답 힌트 요소 없음. 옵션 힌트는 "숫자의 영향권" 만 (`HUD::_flash_influence()`)
- [x] 첫 3섹터 타이밍 판정 면제
  - `SectorData.timing_exempt`

## L10. 사운드 (§17)
- [x] 노트 레인/HIT LINE UI 없음. 3-2-1-GO는 음악+구조음+손상+캐릭터로 전달

## L11. 오디오 마스터 클럭 (§26)
- [x] Timer 반복 금지. 음악 playback position에서 매 프레임 beat/phase 계산
  - `BeatConductor::_process()` — `get_playback_position() + get_time_since_last_mix() - output_latency`
- [x] 프레임 드랍 시 비주얼 이벤트를 현재 오디오 시간으로 재동기화
  - `GameDirector::_process()` 는 경과 beat를 while 루프로 소진 (이벤트 유실 없음)

## L12. 애니메이션 (§14.2)
- [x] 뼈대 포즈(authored)와 귀/머플러 secondary(procedural) 분리
  - `CharacterAnimator` (포즈) / `ScarfChain`,`EarDrag` (procedural)

## L13. 아키텍처 (§25.1)
- [x] MineGrid는 그래픽 없이 단위테스트 가능 — `tests/test_minegrid.gd` (헤드리스)
- [x] Presentation이 퍼즐 정답을 바꾸지 않음 — MineGrid는 Node를 상속하지 않으며 씬 트리를 모름
- [x] PlayerMotor 대시는 물리 impulse가 아닌 목표 셀 기반 authored movement
- [x] LaunchController는 타이밍→궤적이 순수 함수 (`sample(beat)`) 로 재현 가능

## 검증 방법

| 무엇 | 어떻게 확인했나 |
| --- | --- |
| 숫자 법칙 / 유일해 / 50-50 거부 / 도달성 | `테스트.bat` — 54 어서션 전부 통과 |
| 34섹터 체인 (모든 착지 열에서 도달 가능) | `Stage1Data.build()` 가 기동 시 재검증. 실패 시 게임이 뜨지 않음 |
| 정점이 공중 2박에 고정 / 낙하 가속 / 판정 무관 | `test_launch_curve()` — 궤적을 직접 샘플링해 비교 |
| 코어 루프 실주행 | `--sector N --auto` 자동 플레이로 34섹터 완주, 스크린샷 캡처 |
| 카메라 좌우 불변 | `CameraDirector` 가 `rotation`에 yaw/roll을 아예 쓰지 않음 (코드 수준 불변식) |
| 리듬이 대시를 막지 않음 | `PlayerMotor` 가 BeatConductor를 import/참조하지 않음 (코드 수준 불변식) |
| 난이도 곡선 | `test_stage_chain()` 이 추론 깊이 분포와 최대 단서값을 어서션으로 고정 |

## 아트 디렉션 전환 (2D 카툰)

`docs/ARTDIRECTION.md` 가 정본. GDD §15/§16의 "어떻게"를 채운 문서이며,
스위치 세대 커비 시리즈 조사 결과를 근거로 삼는다. 요약:

- 셀셰이딩 + 잉크 외곽선은 **판독 위계를 위한 수단**이다 (§15.3).
  채도와 선 굵기가 둘 다 그 순서를 따른다.
- 외곽선은 법선이 아니라 오브젝트 중심에서 확장하는 inverted hull.
  HAL이 지적한 "겹침 부위에서 외곽선이 깨지는" 문제를 구조적으로 회피한다.
- 폐허는 호러가 아니다. 강·야자수·꽃덩굴·깃발·풍등으로 "한때의 번영"을 보여준다.
- Act마다 하늘·태양·안개 색이 이동한다. 진행도 UI 없이 진행감을 준다 (§33).
- VFX는 자라고 줄어드는 불투명 형태. 폭발 연기는 **도넛**으로 열려 캐릭터 실루엣이
  가운데를 뚫고 나온다 (§16).

## L14. Anti-Goals (§30) — 구현되지 않았음을 확인
- [x] rhythm highway / HIT LINE UI 없음
- [x] 대시 박자 제한 없음
- [x] 상시 정답 힌트(●○/화살표/타일 glow) 없음
- [x] 뒤에서 타일 순차 삭제 붕괴 없음
- [x] 공중 등속/linear jump 없음 (이등분 포물선, 정점 속도 0)
- [x] 즉사/긴 로딩/루프 정지 없음
- [x] Endless 메인 모드 없음
- [x] 떠 있는 독립 플랫폼 나열 아님
- [x] 가짜 3D Canvas 렌더러 아님 (Godot 3D, 실제 depth buffer)
- [x] 카메라 회전에 의한 좌우 반전 없음
