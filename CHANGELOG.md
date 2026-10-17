# Changelog

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
