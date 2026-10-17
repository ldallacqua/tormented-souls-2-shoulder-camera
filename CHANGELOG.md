# Changelog

## 0.3.0 — 2026-10-17

Mira
- Andar mirando no estilo RE4: a Caroline fica voltada para o retículo e o analógico esquerdo a move em qualquer direção relativa à câmera. O jogo só tem o ciclo de caminhada para frente com arma; o mod o toca normalmente para frente, ao contrário para recuar e em passos curtos de lado, e faz o deslocamento com varredura de colisão (desliza em paredes, sobe degraus pequenos, não cai de beirais). `aimMove=false` volta a deixá-la parada com o analógico esquerdo ajustando a mira.
- Mira livre (experimental): o tiro vai para o ponto sob o retículo. O mod ajusta a rotação e o `LineTraceMulti` da munição do jogador (`BP_BaseAmmo`), mantendo a dispersão de pellets. Hooks registrados uma vez, controlados por flag e autodesligáveis em caso de erro.
- Retículo como widget UMG (o `HUD:ReceiveDrawHUD` nunca dispara neste jogo), vermelho sobre inimigos.
- Sensibilidade própria na mira, olhar mais para cima ao mirar, aproximação suave.

Câmera
- Inventário e interações curtas com puzzle/item congelam a visão no ombro em vez de cortar para a câmera fixa e voltar (flicker). Close-ups do jogo continuam aparecendo e o retorno vai direto ao ombro.
- Ao voltar de estados com câmera nativa, o braço é configurado um frame antes da troca de visão.
- Respiração sutil e leve inclinação nas curvas (desligáveis). Sem balanço de passos: causou enjoo no teste. Acompanhamento suave (`followLag`) disponível, desligado.
- Transições suaves de distância/ombro/altura e curva de resposta no analógico direito.

Controles
- L3 troca o ombro (o L3 original só chama o menu de debug).
- Quick turn: analógico para trás + correr/esquivar gira a câmera 180°; o movimento mantém a direção anterior até o analógico ser solto.

Diagnóstico
- Logs `State`, `Native camera during`, `Close-up camera restored`, `Aim start/end`, `Aim probe` e `Free aim`.

Validado no jogo: congelamento no inventário, close-up de puzzle (`BP_MuseumKeyPuzzle`), retículo visível. Validado por medição no jogo: recuo com ciclo invertido, deslocamento por varredura mirando. Pendente: sensação do andar mirando, mira livre com cada arma, quick turn (o botão também pode esquivar), L3, inspeção de itens e documentos.

## 0.2.1 — 2026-10-16

- Correção de snap (~180°) de direção na troca de zonas de câmera (desativação de `AutoNorthLocal` em `BP_RailCamera` e sincronização reforçada de referências de movimento nos ticks).
- Registro resiliente e diferido de ganchos Blueprint para vincular corretamente após o carregamento da fase.
- Colisão da câmera em duas etapas (da cabeça ao ombro, e do ombro para trás), evitando que encostar de costas em paredes colapse a câmera para dentro da cabeça.
- Colisão nativa do SpringArm desativada durante a visão no ombro, centralizando o controle no `collision.lua` (canais Visibility e Camera).
- Filtro de peões e componentes de interface/widgets na colisão (ex: widgets de QTE não empurram mais a câmera).
- Recuperação em geometrias intrincadas (tentativa secundária com raio fino se a varredura inicial começar em penetração).
- Ocultamento dinâmico de Caroline quando a câmera fica a menos de 30 cm da cabeça (com histerese, isolamento de exceções e preservação de lanterna/iluminação).
- Novos testes automatizados cobrindo colisão em duas etapas, câmeras de zona e ocultamento de personagem.

## 0.2.0 — 2026-10-16

- Câmera no ombro com rotação pelo analógico direito e movimento relativo à visão.
- Referências de movimento sincronizadas para evitar mudanças de direção em gatilhos de câmera fixa.
- Atalhos direcionais no D-pad, com eixo vertical corrigido nos três presets de controle.
- Canal de câmera corrigido e varreduras de visibilidade contra paredes/objetos.
- Recuo de câmera baseado na distância real, com retorno suave após obstáculos.
- Câmera congelada durante a pausa para evitar o flash da câmera fixa ao retomar.
- Instalação verificável, configuração, testes de regressão e documentação para manutenção por IA.

Validado manualmente com controle: movimento, rotação, paredes/quadros, atalhos e pausa.
Conhecido: breve flicker ao retornar do inventário ou de interação com item; investigação pendente.
