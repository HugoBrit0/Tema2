const { Pool } = require('pg');

const pool = new Pool({
  host: 'localhost',
  user: 'dsd_user',
  password: 'dsd_pass',
  database: 'dsd_db',
  port: 5432,
});

module.exports = {
  cursos: async () => {
    const { rows } = await pool.query(
      `SELECT id, sigla, nome FROM curso WHERE ativo = TRUE ORDER BY sigla`
    );
    return rows;
  },

  horarioCurso: async ({ cursoId }) => {
    const { rows } = await pool.query(
      `
      SELECT
        j.dia_semana, j.hora_inicio, j.hora_fim,
        u.codigo AS uc_codigo,
        u.nome AS uc_nome,
        t.designacao AS turma,
        s.nome AS sala,
        d.nome AS docente
      FROM aula a
      JOIN turma t ON t.id = a.turma_id
      JOIN uc u ON u.id = t.uc_id
      JOIN curso c ON c.id = t.curso_id
      JOIN janela_horaria j ON j.id = a.janela_id
      JOIN sala s ON s.id = a.sala_id
      JOIN docente d ON d.id = a.docente_id
      WHERE a.ativo = TRUE
        AND c.id = $1
      ORDER BY j.dia_semana, j.hora_inicio
      `,
      [cursoId]
    );
    return rows;
  }
};
