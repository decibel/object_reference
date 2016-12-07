SET LOCAL client_min_messages = WARNING;

DO $$
BEGIN
  CREATE ROLE object_reference__usage NOLOGIN;
EXCEPTION WHEN duplicate_object THEN
  NULL;
END
$$;

/*
 * NOTE: All pg_temp objects must be dropped at the end of the script!
 * Otherwise the eventual DROP CASCADE of pg_temp when the session ends will
 * also drop the extension! Instead of risking problems, create our own
 * "temporary" schema instead.
 */
CREATE SCHEMA __object_reference;
CREATE FUNCTION __object_reference.exec(
  sql text
) RETURNS void LANGUAGE plpgsql AS $body$
BEGIN
  RAISE DEBUG 'sql = %', sql;
  EXECUTE sql;
END
$body$;

CREATE SCHEMA object_reference;
GRANT USAGE ON SCHEMA object_reference TO object_reference__usage;
CREATE SCHEMA _object_reference;

CREATE FUNCTION _object_reference.object_catalog__field(
  object_catalog regclass
) RETURNS name LANGUAGE plpgsql IMMUTABLE
SET search_path FROM CURRENT -- Ensure pg_catalog is in the search_path
AS $body$
DECLARE
  v_reg_type regtype; -- Set if there is a reg* type available
BEGIN
  v_reg_type := cat_tools.object__reg_type(object_catalog);
  IF v_reg_type IN (
      'regclass'
      , 'regconfig'
      , 'regdictionary'
      , 'regoperator'
      , 'regprocedure'
      , 'regtype'
    )  
    THEN
    RETURN v_reg_type;
  END IF;

  RETURN NULL;
END
$body$;
CREATE FUNCTION _object_reference.object_type__field(
  object_type   cat_tools.object_type
) RETURNS name LANGUAGE plpgsql IMMUTABLE AS $body$
DECLARE
  c_catalog CONSTANT regclass := cat_tools.object__catalog(object_type);
  c_field name := _object_reference.object_catalog__field(c_catalog);
BEGIN
  IF c_field IS NULL THEN
    RAISE 'object type "%" is not yet supported', object_type;
  END IF;

  RETURN c_field;
END
$body$;
  
CREATE TABLE _object_reference.object(
  object_id       serial                  PRIMARY KEY
  , object_type   cat_tools.object_type   NOT NULL
  , original_name text                    NOT NULL
  , regclass      regclass
  , regconfig     regconfig
  , regdictionary regdictionary
--  , regnamespace  regnamespace -- SED: REQUIRES 9.5!
  , regoperator   regoperator
  , regprocedure  regprocedure
  -- I don't think we should ever have regrole since we can't create event triggers on it
--  , regrole       regrole -- SED: REQUIRES 9.5!
  , regtype       regtype
  , CONSTRAINT only_one_object_field_may_be_not_null
      CHECK( not_null_count(
          regclass::text
          , regconfig::text
          , regdictionary::text
          --, regnamespace -- SED: REQUIRES 9.5!
          , regoperator::text
          , regprocedure::text
          , regtype::text
        ) = 1
      )
);
CREATE UNIQUE INDEX object__u_regclass ON _object_reference.object(regclass) WHERE regclass IS NOT NULL;
CREATE UNIQUE INDEX object__u_regconfig ON _object_reference.object(regconfig) WHERE regconfig IS NOT NULL;
CREATE UNIQUE INDEX object__u_regdictionary ON _object_reference.object(regdictionary) WHERE regdictionary IS NOT NULL;
CREATE UNIQUE INDEX object__u_regoperator ON _object_reference.object(regoperator) WHERE regoperator IS NOT NULL;
CREATE UNIQUE INDEX object__u_regprocedure ON _object_reference.object(regprocedure) WHERE regprocedure IS NOT NULL;
CREATE UNIQUE INDEX object__u_regtype ON _object_reference.object(regtype) WHERE regtype IS NOT NULL;

CREATE FUNCTION object_reference.object__getsert(
  object_type   cat_tools.object_type
  , object_name text
) RETURNS int LANGUAGE plpgsql AS $body$
DECLARE
  c_field CONSTANT name := _object_reference.object_type__field(object_type);

  c_select CONSTANT text := format(
      'SELECT * FROM _object_reference.object WHERE %I = $1'
      , c_field
    )
  ;

  c_insert CONSTANT text := format(
      'INSERT INTO _object_reference.object(object_type, original_name, %I) VALUES($1, $2, $2) RETURNING *'
      , c_field
    )
  ;

  r_obj _object_reference.object;
  i smallint;
BEGIN
  FOR i IN 1..10 LOOP
    EXECUTE c_select
      INTO r_obj
      USING object_name
    ;
    IF FOUND THEN
      RETURN r_obj.object_id;
    END IF;

    BEGIN
      EXECUTE c_insert
        INTO r_obj
        USING object_type, object_name
      ;
      RETURN r_obj.object_id;
    --EXCEPTION WHEN 
    END;
  END LOOP;

  RAISE 'fell out of loop!' USING HINT = 'This should never happen.';
END
$body$;


/*
 * Drop "temporary" objects
 */
DROP FUNCTION __object_reference.exec(
  sql text
);
DROP SCHEMA __object_reference;

-- vi: expandtab sw=2 ts=2