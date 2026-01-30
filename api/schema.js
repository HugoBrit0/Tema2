const { buildSchema } = require('graphql');

module.exports = buildSchema(`
  type Curso {
    id: ID!
    sigla: String!
    nome: String!
  }

  type Aula {
    dia_semana: Int
    hora_inicio: String
    hora_fim: String
    uc_codigo: String
    uc_nome: String
    turma: String
    sala: String
    docente: String
  }

  type Query {
    cursos: [Curso]
    horarioCurso(cursoId: ID!): [Aula]
  }
`);
