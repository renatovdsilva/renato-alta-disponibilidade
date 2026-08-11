# 12 — Como trabalhar com esta documentação

## Ferramenta escolhida: MkDocs Material

A documentação está em Markdown simples. O MkDocs Material transforma essas páginas num site com pesquisa, índice lateral, modo escuro e botões de copiar nos blocos de código — e publica-o gratuitamente no GitHub Pages.

**Porquê esta e não outra:**

| Ferramenta | Prós | Contras | Veredicto |
|---|---|---|---|
| **MkDocs Material** | Markdown puro, configuração num só ficheiro, pesquisa offline, publica no GitHub Pages | precisa de Python | **escolhida** |
| Docusaurus | muito completo, React | exige Node e mais manutenção | exagerado para isto |
| GitBook | bonito, sem instalação | serviço externo, plano pago | dependência desnecessária |
| Obsidian | excelente para escrever e ligar notas | não publica site | **complementar** — usar para editar |
| Notion | fácil | não vive no Git | não serve para portfólio técnico |

Para um portefólio de infraestrutura, MkDocs Material é também a escolha mais coerente: a documentação vive no mesmo repositório que o código, versiona-se com ele e publica-se por pipeline.

---

## Ver o site localmente

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-docs.txt
mkdocs serve
```

Abrir `http://127.0.0.1:8000`. Guardar um ficheiro recarrega a página automaticamente.

---

## Publicar

O workflow `.github/workflows/docs.yml` publica automaticamente a cada push para `main` que toque em `docs/` ou `mkdocs.yml`.

Configuração única no GitHub: **Settings → Pages → Source: GitHub Actions**.

O site fica em `https://renatovdsilva.github.io/renato-alta-disponibilidade/`.

---

## Escrever

Para editar confortavelmente, qualquer uma serve:

- **VS Code** — com as extensões *Markdown All in One* e *YAML*. É a escolha natural, já que o código está lá.
- **Obsidian** — apontar o cofre para a pasta `docs/`. Melhor para escrever texto longo e ligar páginas entre si.
- Direto no GitHub — o botão de editar no site leva ao ficheiro certo.

---

## Convenções desta documentação

1. **Um documento por processo**, numerado pela ordem em que se executa.
2. **Cada documento tem uma tabela de registo no fim** — data, ação, resultado. É o que transforma documentação em diário técnico.
3. **Comandos sempre em blocos copiáveis**, sem `$` no início, para poderem ser colados diretamente.
4. **Decisões explicadas com alternativas e custo**, nunca só a conclusão.
5. **Números medidos vão para `11-metricas.md`**, nunca estimados.
6. **Erros ficam registados em `09-troubleshooting.md`** com causa e solução.

---

## Validação automática

O workflow `.github/workflows/lint.yml` corre a cada push:

- valida a sintaxe de todos os manifests Kubernetes
- corre `helm lint` e `helm template` no chart
- passa `shellcheck` pelos scripts

O `mkdocs build --strict` falha se houver ligações internas partidas — o que impede documentação com links mortos.
