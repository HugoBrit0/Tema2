const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');

const app = express();
app.use(cors());
app.use(express.json());

// PostgreSQL (container exposto em localhost:5432)
const pool = new Pool({
  host: '127.0.0.1',
  port: 5432,
  user: 'dsd_user',
  password: 'dsd_pass',
  database: 'dsd_db',
});

// Health check
app.get('/health', (req, res) => res.json({ ok: true }));

// GET /salas
app.get('/salas', async (req, res) => {
  try {
    const { rows } = await pool.query(`
      SELECT s.id, s.nome, s.edificio, s.campus, s.lotacao, s.ativo,
             ts.codigo AS tipo_sala
      FROM sala s
      JOIN tipo_sala ts ON ts.id = s.tipo_sala_id
      ORDER BY s.nome
    `);
    res.json(rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ erro: 'Erro ao obter salas' });
  }
});

// GET /turmas
app.get('/turmas', async (req, res) => {
  try {
    const { rows } = await pool.query(`
      SELECT t.id, t.designacao, t.numero_alunos, t.ativo,
             c.sigla AS curso_sigla, c.nome AS curso_nome,
             u.codigo AS uc_codigo, u.nome AS uc_nome
      FROM turma t
      JOIN curso c ON c.id = t.curso_id
      JOIN uc u ON u.id = t.uc_id
      ORDER BY c.sigla, u.codigo, t.designacao
    `);
    res.json(rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ erro: 'Erro ao obter turmas' });
  }
});

// GET /aulas
app.get('/aulas', async (req, res) => {
  try {
    const { rows } = await pool.query(`
      SELECT a.id,
             d.id AS docente_id, d.nome AS docente,
             s.id AS sala_id, s.nome AS sala,
             j.id AS janela_id, j.dia_semana, j.hora_inicio, j.hora_fim,
             u.codigo AS uc_codigo, u.nome AS uc_nome,
             t.designacao AS turma
      FROM aula a
      JOIN docente d ON d.id = a.docente_id
      JOIN sala s ON s.id = a.sala_id
      JOIN janela_horaria j ON j.id = a.janela_id
      JOIN turma t ON t.id = a.turma_id
      JOIN uc u ON u.id = t.uc_id
      WHERE a.ativo = TRUE
      ORDER BY j.dia_semana, j.hora_inicio, s.nome
    `);
    res.json(rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ erro: 'Erro ao obter aulas' });
  }
});
// POST /aulas
// body: { turma_id, docente_id, sala_id, janela_id, tipo_hora_id (opcional), observacoes (opcional) }
app.post('/aulas', async (req, res) => {
  const { turma_id, docente_id, sala_id, janela_id, tipo_hora_id, observacoes } = req.body ?? {};

  // Validação básica (400)
  const toInt = (v) => (v === undefined || v === null || v === '' ? null : Number(v));
  const turmaId = toInt(turma_id);
  const docenteId = toInt(docente_id);
  const salaId = toInt(sala_id);
  const janelaId = toInt(janela_id);
  const tipoHoraId = toInt(tipo_hora_id);

  if (![turmaId, docenteId, salaId, janelaId].every((n) => Number.isInteger(n) && n > 0)) {
    return res.status(400).json({
      erro: 'Dados inválidos. É obrigatório enviar turma_id, docente_id, sala_id e janela_id (inteiros > 0).',
    });
  }
  if (tipoHoraId !== null && !(Number.isInteger(tipoHoraId) && tipoHoraId > 0)) {
    return res.status(400).json({ erro: 'tipo_hora_id inválido (tem de ser inteiro > 0) ou omisso.' });
  }

  try {
    // Pré-validações (404) — para não devolver apenas erro genérico da FK
    const checks = await pool.query(
      `
      SELECT
        EXISTS (SELECT 1 FROM turma WHERE id = $1)  AS turma_ok,
        EXISTS (SELECT 1 FROM docente WHERE id = $2) AS docente_ok,
        EXISTS (SELECT 1 FROM sala WHERE id = $3)    AS sala_ok,
        EXISTS (SELECT 1 FROM janela_horaria WHERE id = $4) AS janela_ok,
        ($5::int IS NULL OR EXISTS (SELECT 1 FROM tipo_hora WHERE id = $5)) AS tipo_hora_ok
      `,
      [turmaId, docenteId, salaId, janelaId, tipoHoraId]
    );

    const c = checks.rows[0];
    if (!c.turma_ok) return res.status(404).json({ erro: `Turma não encontrada (id=${turmaId}).` });
    if (!c.docente_ok) return res.status(404).json({ erro: `Docente não encontrado (id=${docenteId}).` });
    if (!c.sala_ok) return res.status(404).json({ erro: `Sala não encontrada (id=${salaId}).` });
    if (!c.janela_ok) return res.status(404).json({ erro: `Janela horária não encontrada (id=${janelaId}).` });
    if (!c.tipo_hora_ok) return res.status(404).json({ erro: `Tipo de hora não encontrado (id=${tipoHoraId}).` });

    // Insert — as regras “hard” são garantidas pela BD (EXCLUDE + trigger lotação)
    const { rows } = await pool.query(
      `
      INSERT INTO aula (turma_id, docente_id, sala_id, janela_id, tipo_hora_id, observacoes, ativo)
      VALUES ($1, $2, $3, $4, $5, $6, TRUE)
      RETURNING id, turma_id, docente_id, sala_id, janela_id, tipo_hora_id, observacoes, ativo
      `,
      [turmaId, docenteId, salaId, janelaId, tipoHoraId, observacoes ?? null]
    );

    return res.status(201).json(rows[0]);
  } catch (e) {
    console.error(e);

    // Mapeamento de erros comuns do PostgreSQL
    // 23P01 = exclusion violation (conflitos de docente/sala na mesma janela)
    if (e.code === '23P01') {
      return res.status(409).json({ erro: 'Conflito de horário (docente ou sala já ocupados nessa janela).' });
    }

    // 23503 = foreign key violation (caso escapasse algo)
    if (e.code === '23503') {
      return res.status(400).json({ erro: 'Referência inválida (FK). Verifica os IDs enviados.' });
    }

    // 23514 = check violation
    if (e.code === '23514') {
      return res.status(400).json({ erro: 'Validação falhou (CHECK). Verifica os dados enviados.' });
    }

    // Trigger de lotação usa RAISE EXCEPTION -> normalmente P0001
    if (e.code === 'P0001') {
      return res.status(409).json({ erro: e.message }); // ex.: lotação insuficiente
    }

    return res.status(500).json({ erro: 'Erro ao criar aula' });
  }
});

// GET /horario/docente/:id
app.get('/horario/docente/:id', async (req, res) => {
  try {
    const docenteId = Number(req.params.id);
    const { rows } = await pool.query(`
      SELECT j.dia_semana, j.hora_inicio, j.hora_fim,
             u.codigo AS uc_codigo, u.nome AS uc_nome,
             t.designacao AS turma,
             s.nome AS sala
      FROM aula a
      JOIN janela_horaria j ON j.id = a.janela_id
      JOIN turma t ON t.id = a.turma_id
      JOIN uc u ON u.id = t.uc_id
      JOIN sala s ON s.id = a.sala_id
      WHERE a.ativo = TRUE AND a.docente_id = $1
      ORDER BY j.dia_semana, j.hora_inicio
    `, [docenteId]);
    res.json(rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ erro: 'Erro ao obter horário do docente' });
  }
});

// GET /horario/sala/:id
app.get('/horario/sala/:id', async (req, res) => {
  try {
    const salaId = Number(req.params.id);
    const { rows } = await pool.query(`
      SELECT j.dia_semana, j.hora_inicio, j.hora_fim,
             u.codigo AS uc_codigo, u.nome AS uc_nome,
             t.designacao AS turma,
             d.nome AS docente
      FROM aula a
      JOIN janela_horaria j ON j.id = a.janela_id
      JOIN turma t ON t.id = a.turma_id
      JOIN uc u ON u.id = t.uc_id
      JOIN docente d ON d.id = a.docente_id
      WHERE a.ativo = TRUE AND a.sala_id = $1
      ORDER BY j.dia_semana, j.hora_inicio
    `, [salaId]);
    res.json(rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ erro: 'Erro ao obter horário da sala' });
  }
});
// DELETE /aulas/:id (inativar)
app.delete('/aulas/:id', async (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) {
      return res.status(400).json({ erro: 'ID inválido.' });
    }

    const { rowCount, rows } = await pool.query(
      `
      UPDATE aula
         SET ativo = FALSE
       WHERE id = $1 AND ativo = TRUE
       RETURNING id, ativo
      `,
      [id]
    );

    if (rowCount === 0) {
      return res.status(404).json({ erro: `Aula não encontrada ou já inativa (id=${id}).` });
    }

    res.json({ ok: true, aula: rows[0] });
  } catch (e) {
    console.error(e);
    res.status(500).json({ erro: 'Erro ao inativar aula' });
  }
});
// GET /horario/curso/:id
app.get('/horario/curso/:id', async (req, res) => {
  try {
    const cursoId = Number(req.params.id);
    if (!Number.isInteger(cursoId) || cursoId <= 0) {
      return res.status(400).json({ erro: 'ID de curso inválido.' });
    }

    const { rows } = await pool.query(
      `
      SELECT
        j.dia_semana, j.hora_inicio, j.hora_fim,
        u.codigo AS uc_codigo, u.nome AS uc_nome,
        t.designacao AS turma,
        s.nome AS sala,
        d.nome AS docente
      FROM aula a
      JOIN turma t ON t.id = a.turma_id
      JOIN curso c ON c.id = t.curso_id
      JOIN uc u ON u.id = t.uc_id
      JOIN janela_horaria j ON j.id = a.janela_id
      JOIN sala s ON s.id = a.sala_id
      JOIN docente d ON d.id = a.docente_id
      WHERE a.ativo = TRUE
        AND t.ativo = TRUE
        AND c.id = $1
      ORDER BY j.dia_semana, j.hora_inicio, u.codigo, t.designacao
      `,
      [cursoId]
    );

    res.json(rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ erro: 'Erro ao obter horário do curso' });
  }
});
// GET /janelas
app.get('/janelas', async (req, res) => {
  try {
    const { rows } = await pool.query(`
      SELECT id, dia_semana, hora_inicio, hora_fim
      FROM janela_horaria
      ORDER BY dia_semana, hora_inicio
    `);
    res.json(rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ erro: 'Erro ao obter janelas horárias' });
  }
});

// GET /docentes
app.get('/docentes', async (req, res) => {
  try {
    const { rows } = await pool.query(`
      SELECT id, nome, email_institucional
      FROM docente
      WHERE ativo = TRUE
      ORDER BY nome
    `);
    res.json(rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ erro: 'Erro ao obter docentes' });
  }
});

// GET /cursos
app.get('/cursos', async (req, res) => {
  try {
    const { rows } = await pool.query(`
      SELECT id, sigla, nome
      FROM curso
      WHERE ativo = TRUE
      ORDER BY sigla
    `);
    res.json(rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ erro: 'Erro ao obter cursos' });
  }
});
// GET /horario/curso/:id
app.get('/horario/curso/:id', async (req, res) => {
  try {
    const cursoId = Number(req.params.id);
    if (!Number.isInteger(cursoId) || cursoId <= 0) {
      return res.status(400).json({ erro: 'ID de curso inválido.' });
    }

    const { rows } = await pool.query(
      `
      SELECT
        j.dia_semana, j.hora_inicio, j.hora_fim,
        c.sigla AS curso_sigla,
        u.codigo AS uc_codigo, u.nome AS uc_nome,
        t.designacao AS turma,
        s.nome AS sala,
        d.nome AS docente
      FROM aula a
      JOIN turma t ON t.id = a.turma_id
      JOIN curso c ON c.id = t.curso_id
      JOIN uc u ON u.id = t.uc_id
      JOIN janela_horaria j ON j.id = a.janela_id
      JOIN sala s ON s.id = a.sala_id
      JOIN docente d ON d.id = a.docente_id
      WHERE a.ativo = TRUE
        AND t.ativo = TRUE
        AND c.id = $1
      ORDER BY j.dia_semana, j.hora_inicio, u.codigo, t.designacao
      `,
      [cursoId]
    );

    return res.json(rows);
  } catch (e) {
    console.error(e);
    return res.status(500).json({ erro: 'Erro ao obter horário do curso' });
  }
});
// GET /horario/curso/:id
app.get('/horario/curso/:id', async (req, res) => {
  try {
    const cursoId = Number(req.params.id);
    if (!Number.isInteger(cursoId) || cursoId <= 0) {
      return res.status(400).json({ erro: 'ID de curso inválido.' });
    }

    const { rows } = await pool.query(
      `
      SELECT
        j.dia_semana, j.hora_inicio, j.hora_fim,
        c.sigla AS curso_sigla,
        u.codigo AS uc_codigo, u.nome AS uc_nome,
        t.designacao AS turma,
        s.nome AS sala,
        d.nome AS docente
      FROM aula a
      JOIN turma t ON t.id = a.turma_id
      JOIN curso c ON c.id = t.curso_id
      JOIN uc u ON u.id = t.uc_id
      JOIN janela_horaria j ON j.id = a.janela_id
      JOIN sala s ON s.id = a.sala_id
      JOIN docente d ON d.id = a.docente_id
      WHERE a.ativo = TRUE
        AND t.ativo = TRUE
        AND c.id = $1
      ORDER BY j.dia_semana, j.hora_inicio, u.codigo, t.designacao
      `,
      [cursoId]
    );

    return res.json(rows);
  } catch (e) {
    console.error(e);
    return res.status(500).json({ erro: 'Erro ao obter horário do curso' });
  }
});
// GET /cursos
app.get('/cursos', async (req, res) => {
  try {
    const { rows } = await pool.query(`
      SELECT id, sigla, nome
      FROM curso
      WHERE ativo = TRUE
      ORDER BY sigla
    `);
    res.json(rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ erro: 'Erro ao obter cursos' });
  }
});

// GET /docentes
app.get('/docentes', async (req, res) => {
  try {
    const { rows } = await pool.query(`
      SELECT id, nome, email_institucional
      FROM docente
      WHERE ativo = TRUE
      ORDER BY nome
    `);
    res.json(rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ erro: 'Erro ao obter docentes' });
  }
});

// GET /janelas
app.get('/janelas', async (req, res) => {
  try {
    const { rows } = await pool.query(`
      SELECT id, dia_semana, hora_inicio, hora_fim
      FROM janela_horaria
      ORDER BY dia_semana, hora_inicio
    `);
    res.json(rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ erro: 'Erro ao obter janelas horárias' });
  }
});
// POST /horarios/gerar
// body opcional: { curso_id, max_por_turma }
// - curso_id: gera apenas para turmas desse curso (opcional)
// - max_por_turma: limite de aulas a gerar por turma (opcional, default 10)
app.post('/horarios/gerar', async (req, res) => {
  const cursoId = req.body?.curso_id ? Number(req.body.curso_id) : null;
  const maxPorTurma = req.body?.max_por_turma ? Number(req.body.max_por_turma) : 10;

  if (cursoId !== null && (!Number.isInteger(cursoId) || cursoId <= 0)) {
    return res.status(400).json({ erro: 'curso_id inválido.' });
  }
  if (!Number.isInteger(maxPorTurma) || maxPorTurma <= 0 || maxPorTurma > 50) {
    return res.status(400).json({ erro: 'max_por_turma inválido (1..50).' });
  }

  // Helpers
  const pickDocenteId = async (ucId) => {
    const r = await pool.query(`SELECT responsavel_id FROM uc WHERE id=$1`, [ucId]);
    const rid = r.rows?.[0]?.responsavel_id;
    if (rid) return rid;

    const d = await pool.query(`SELECT id FROM docente WHERE ativo=TRUE ORDER BY id LIMIT 1`);
    return d.rows?.[0]?.id ?? null;
  };

  // Regra simples de compatibilidade tipo_hora -> tipo_sala
  // PL -> LAB; resto -> TEO (ou qualquer se não existir)
  const salaTipoPreferido = (tipoHoraCodigo) => {
    if (tipoHoraCodigo === 'PL') return 'LAB';
    return 'TEO';
  };

  try {
    // 1) Buscar turmas alvo
    const turmasQ = await pool.query(
      `
      SELECT t.id AS turma_id, t.numero_alunos, t.uc_id, t.curso_id,
             u.codigo AS uc_codigo, u.nome AS uc_nome,
             c.sigla AS curso_sigla
      FROM turma t
      JOIN uc u ON u.id = t.uc_id
      JOIN curso c ON c.id = t.curso_id
      WHERE t.ativo = TRUE
        AND ($1::int IS NULL OR t.curso_id = $1)
      ORDER BY t.id
      `,
      [cursoId]
    );

    const turmas = turmasQ.rows;
    if (turmas.length === 0) {
      return res.json({ ok: true, criado: 0, mensagem: 'Sem turmas para gerar.' });
    }

    // 2) Buscar janelas
    const janelasQ = await pool.query(
      `SELECT id, dia_semana, hora_inicio, hora_fim FROM janela_horaria ORDER BY dia_semana, hora_inicio`
    );
    const janelas = janelasQ.rows;

    if (janelas.length === 0) {
      return res.status(400).json({ erro: 'Não existem janelas_horaria. Cria janelas antes de gerar.' });
    }

    // 3) Buscar salas (com tipo)
    const salasQ = await pool.query(
      `
      SELECT s.id, s.lotacao, ts.codigo AS tipo_sala
      FROM sala s
      JOIN tipo_sala ts ON ts.id = s.tipo_sala_id
      WHERE s.ativo = TRUE
      ORDER BY s.lotacao DESC
      `
    );
    const salas = salasQ.rows;

    if (salas.length === 0) {
      return res.status(400).json({ erro: 'Não existem salas ativas. Cria salas antes de gerar.' });
    }

    // 4) Para cada turma, descobrir “sessões” (uc_tipo_hora)
    // Se uc_tipo_hora existir, gera X aulas por tipo (onde X = horas, arredondado para cima / 1).
    // Se não existir, gera 1 aula teórica (T).
    let criadoTotal = 0;
    const detalhes = [];

    for (const t of turmas) {
      const turmaId = t.turma_id;
      const ucId = t.uc_id;

      const docenteId = await pickDocenteId(ucId);
      if (!docenteId) {
        detalhes.push({
          turma_id: turmaId,
          uc: t.uc_codigo,
          criado: 0,
          erro: 'Sem docente disponível (uc sem responsavel_id e sem docentes ativos).',
        });
        continue;
      }

      // sessões por tipo
      const tiposQ = await pool.query(
        `
        SELECT th.id AS tipo_hora_id, th.codigo AS tipo_hora_codigo, uth.horas
        FROM uc_tipo_hora uth
        JOIN tipo_hora th ON th.id = uth.tipo_hora_id
        WHERE uth.uc_id = $1
        ORDER BY th.codigo
        `,
        [ucId]
      );

      let sessoes = [];
      if (tiposQ.rows.length === 0) {
        // fallback: 1 teórica
        const tQ = await pool.query(`SELECT id FROM tipo_hora WHERE codigo='T' LIMIT 1`);
        const tipoT = tQ.rows?.[0]?.id ?? null;

        if (!tipoT) {
          detalhes.push({ turma_id: turmaId, uc: t.uc_codigo, criado: 0, erro: "Sem tipo_hora 'T'." });
          continue;
        }
        sessoes = [{ tipo_hora_id: tipoT, tipo_hora_codigo: 'T', quantidade: 1 }];
      } else {
        // regra simples: 1 aula por cada "hora" (podes ajustar depois)
        sessoes = tiposQ.rows.map(r => ({
          tipo_hora_id: r.tipo_hora_id,
          tipo_hora_codigo: r.tipo_hora_codigo,
          quantidade: Math.min(Math.max(Number(r.horas) || 1, 1), maxPorTurma),
        }));
      }

      // limitar total por turma
      let totalPretendido = sessoes.reduce((acc, s) => acc + s.quantidade, 0);
      if (totalPretendido > maxPorTurma) {
        // corta proporcionalmente, simples
        let sobra = maxPorTurma;
        sessoes = sessoes.map(s => {
          const q = Math.max(0, Math.min(s.quantidade, sobra));
          sobra -= q;
          return { ...s, quantidade: q };
        }).filter(s => s.quantidade > 0);
      }

      let criadoTurma = 0;
      const falhas = [];

      for (const s of sessoes) {
        const pref = salaTipoPreferido(s.tipo_hora_codigo);

        // ordenar salas: preferidas primeiro, e por lotação desc
        const salasOrdenadas = [
          ...salas.filter(x => x.tipo_sala === pref),
          ...salas.filter(x => x.tipo_sala !== pref),
        ];

        for (let i = 0; i < s.quantidade; i++) {
          let inseriu = false;

          // tenta todas as combinações janela x sala
          for (const j of janelas) {
            for (const sala of salasOrdenadas) {
              try {
                await pool.query(
                  `
                  INSERT INTO aula (turma_id, docente_id, sala_id, janela_id, tipo_hora_id, observacoes, ativo)
                  VALUES ($1,$2,$3,$4,$5,$6, TRUE)
                  `,
                  [
                    turmaId,
                    docenteId,
                    sala.id,
                    j.id,
                    s.tipo_hora_id,
                    `Gerado automaticamente (${t.curso_sigla} / ${t.uc_codigo} / ${s.tipo_hora_codigo})`,
                  ]
                );
                criadoTurma += 1;
                criadoTotal += 1;
                inseriu = true;
                break;
              } catch (e) {
                // 23P01 = conflito EXCLUDE (sala/docente ocupados na janela)
                // P0001 = trigger lotação
                // outros erros: tenta próxima combinação
                continue;
              }
            }
            if (inseriu) break;
          }

          if (!inseriu) {
            falhas.push({
              tipo_hora: s.tipo_hora_codigo,
              msg: 'Não foi possível encontrar combinação sala/janela válida (conflitos ou lotação).',
            });
          }
        }
      }

      detalhes.push({
        turma_id: turmaId,
        curso: t.curso_sigla,
        uc: t.uc_codigo,
        criado: criadoTurma,
        falhas,
      });
    }

    return res.json({
      ok: true,
      criado: criadoTotal,
      turmas_processadas: turmas.length,
      detalhes,
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ erro: 'Erro no gerador automático' });
  }
});

const PORT = 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`API REST a correr em http://0.0.0.0:${PORT}`);
});
