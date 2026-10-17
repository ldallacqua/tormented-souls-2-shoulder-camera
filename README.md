# Tormented Souls 2 — Shoulder Camera

Mod experimental de câmera no ombro para **Tormented Souls 2 no Windows**, inspirado no enquadramento de Resident Evil 4 Remake. Feito com scripts Lua e UE4SS, sem alterar os arquivos de conteúdo do jogo.

O analógico esquerdo movimenta a personagem em relação à câmera; o direito gira a visão. Os quatro atalhos direcionais de itens passam para o D-pad durante a exploração. Inventário, menus e puzzles mantêm os próprios mapeamentos.

## Instalação

1. Baixe o ZIP em [Releases](https://github.com/ldallacqua/tormented-souls-2-shoulder-camera/releases) e extraia em uma pasta.
2. Feche o jogo e execute `Instalar.cmd`.
3. Informe a pasta `TormentedSouls2\Binaries\Win64`, que contém `TormentedSouls2-Win64-Shipping.exe`.
4. Abra o jogo normalmente e carregue uma partida.

O instalador verifica a versão do executável e a integridade do pacote. Ele recusa instalações de UE4SS desconhecidas para evitar sobrescrever outros mods. Para uma instalação manual com UE4SS existente, integre a pasta `TormentedShoulderCamera` ao seu diretório `Mods`, acrescente `TormentedShoulderCamera : 1` ao `mods.txt` e use a versão de runtime indicada abaixo.

## Controles

| Controle | Função |
| --- | --- |
| Analógico esquerdo | Movimento relativo à câmera |
| Analógico direito | Girar câmera e olhar para cima/baixo |
| D-pad ↑ ↓ ← → | Quatro atalhos direcionais originais |
| Clique do analógico direito | Atalho central original |
| Clique do analógico esquerdo (L3) | Trocar o ombro |
| Analógico esquerdo para trás + correr/esquivar | Quick turn de 180° |
| Mirar + analógico esquerdo | Anda mirando em qualquer direção (estilo RE4), voltada para o retículo; o tiro segue o retículo |
| F6 | Alternar câmera do mod/original; restaurar os atalhos originais |
| F7 | Trocar o ombro |
| Home | Centralizar atrás da personagem |

O D-pad deixa de movimentar a personagem durante a exploração com o mod ativo. Os três presets de controle originais são contemplados. Teclado e controles de menus não são remapeados.

## Configuração e remoção

Com o jogo fechado, edite `ue4ss/Mods/TormentedShoulderCamera/Scripts/config.lua`: distância, altura, ombro, FOV, sensibilidade, curva do analógico, zona morta, eixo vertical, raio de colisão, mira livre, inclinação do tronco, marcas de tiro, retículo, botão de troca de ombro e quick turn. Quem atualiza mantém o `config.lua` antigo; sem a linha `impactMarks=true`, as marcas de tiro ficam desligadas.

Use `Desativar.cmd`/`Ativar.cmd` para desativar ou ativar entre partidas. Para remover, exclua a pasta do mod e sua linha em `ue4ss/Mods/mods.txt`. Caso nenhum outro mod use UE4SS, também é possível remover o `dwmapi.dll` e a pasta `ue4ss` adicionados pelo pacote. O instalador não modifica executáveis, conteúdo `.pak/.ucas/.utoc` ou saves do jogo.

## Funcionamento e limites

- Mantém a câmera da personagem como alvo ao atravessar gatilhos das câmeras fixas, evitando flashes dessas câmeras.
- Atualiza as referências de direção que o jogo usa para o movimento, incluindo as referências das transições de câmera.
- Usa o braço de câmera nativo e varreduras esféricas de visibilidade contra colisão simples e geometria detalhada. Recolhe imediatamente diante de obstáculos e retorna suavemente à distância normal.
- Congela a visão no ombro na pausa, no inventário e em interações curtas com puzzles/itens. Close-ups do próprio jogo, cinemáticas, diálogos e outros estados detectados usam a câmera original.
- Movimento de câmera sutil: respiração e inclinação leve nas curvas (`sway`/`swayAmount` no config). Sem balanço de passos.
- Mira livre experimental: ao mirar, a personagem gira com a câmera e o tiro vai para o centro da tela. O tronco inclina para o retículo dentro do limite da animação do jogo (30° para baixo, 40° para cima); além disso o tiro ainda vai ao retículo, mas a arma não acompanha. A câmera não desce além de -35° na mira e nenhum tiro sai mais inclinado que 50° para baixo, para não acertar os próprios pés. Marcas escuras mostram onde cada tiro bateu (`impactMarks=false` desliga). Desative tudo com `freeAim=false` para voltar à mira assistida do jogo.
- Andar mirando: para frente usa a caminhada mirando do jogo; para trás, a mesma caminhada tocada ao contrário (arma erguida); para os lados, os passos laterais da Caroline. O recuo com a arma erguida depende de mapear a caminhada mirando de cada arma: a Nailgun foi medida no jogo; pregadora automática, Hand Cannon, martelo e pé de cabra estão mapeados pelo nome da animação, sem validação. Outras armas usam o recuo genérico, que abaixa a arma. Teclado não move a personagem enquanto mira.

É um protótipo: os testes não cobrem a campanha inteira, todos os puzzles, chefes ou cinematics. Espaços muito apertados podem aproximar a câmera da personagem. Objetos sem geometria de colisão consultável podem continuar apresentando problemas. Cenários feitos para ângulos fixos podem revelar superfícies sem acabamento. F6 permite voltar à câmera original.

### Compatibilidade

- Executável de Windows testado com Unreal Engine **5.5.4**.
- SHA-256 do executável testado: `6c71ab55143add71e56c9477cdbfcb8f44e16d8d5c4df7c8c678396a6275cb4f`.
- Runtime fixado: **UE4SS 3.0.1-1176-g1ba38db4**. Outras versões do jogo/runtime não foram validadas.

## Desenvolvimento

`src/TormentedShoulderCamera/Scripts` contém os scripts distribuídos. `camera.lua` controla câmera/movimento, `input.lua` remapeia os contextos de exploração e `collision.lua` calcula a distância segura.

Para gerar o pacote com Python 3.11 ou mais recente:

```powershell
python tools/build.py
# Ou reutilize o ZIP oficial já baixado:
python tools/build.py --runtime-zip caminho/UE4SS_v3.0.1-1176-g1ba38db4.zip
```

O build baixa somente o runtime oficial, confere seu SHA-256 e gera o pacote em `dist`. O repositório não contém arquivos proprietários do jogo, saves, dumps de memória ou credenciais.

Para executar os testes de lógica com Lua 5.4:

```powershell
lua tests/run.lua
```

Os testes cobrem remapeamento/restauração dos três presets, preservação de teclado/menus e recuo/retorno da colisão. Incluem uma regressão observada no runtime: o booleano compactado `bStartPenetrating` pode ser lido como verdadeiro em colisões distantes, apesar de `Time`/`Distance` estarem corretos. A solução usa `Time` e não colapsa a câmera por causa desse sinalizador. Testes de lógica não substituem validação visual dentro do jogo.

## Créditos

Scripts do mod: licença MIT. Runtime [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS), sob licença MIT incluída separadamente no pacote. Referências de implementação: documentação oficial de [Enhanced Input](https://dev.epicgames.com/documentation/en-us/unreal-engine/enhanced-input-in-unreal-engine) e [Spring Arm](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/USpringArmComponent). Projeto não oficial, sem afiliação aos criadores do jogo.
