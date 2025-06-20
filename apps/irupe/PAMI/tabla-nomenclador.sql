-- #############################################################################
-- Diseño de Tabla Única para Nomenclador de Prácticas
-- #############################################################################

-- Esta definición crea una única tabla para contener todos los datos del nomenclador.
-- Es una solución simple y directa, ideal para contextos donde se priorizan
-- consultas sencillas sobre la normalización de datos.

CREATE TABLE nomenclador_completo (
    -- Código del módulo al que pertenece la práctica.
    codigo_modulo INTEGER,

    -- Descripción textual del módulo. Este valor se repetirá en varias filas.
    descripcion_modulo TEXT,

    -- Código de la práctica. Se define como PRIMARY KEY, lo que garantiza que
    -- cada valor en esta columna sea único y no nulo.
    -- Un índice único se crea automáticamente para esta columna.
    codigo_practica INTEGER PRIMARY KEY,

    -- Descripción detallada de la práctica médica.
    descripcion_practica TEXT,

    -- Fecha en que la práctica entra en vigencia.
    inicio_vigencia DATE,

    -- Monto de los honorarios. Se utiliza NUMERIC para una precisión exacta
    -- en valores monetarios, evitando errores de redondeo.
    honorarios NUMERIC(10, 2),

    -- Monto de los gastos asociados a la práctica.
    gastos NUMERIC(10, 2),

    -- Tipo de práctica (ej. 'CONSULTA MEDICA (I)', 'IMAGENES (I-II)').
    tipo TEXT,

    -- Nivel de autorización requerido. Puede ser nulo si no aplica.
    nivel_autorizacion TEXT,

    -- Campo para cualquier observación o nota adicional. Puede ser nulo.
    observaciones TEXT
);
