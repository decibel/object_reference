SET LOCAL client_min_messages = WARNING;

-- This BS is because count_nulls is relocatable, so could be in any schema
DO $$
BEGIN
  RAISE DEBUG 'initial search_path = %', current_setting('search_path');
  PERFORM set_config('search_path', current_setting('search_path') || ', ' || extnamespace::regnamespace::text, true) -- true = local only
    FROM pg_extension
    WHERE extname = 'count_nulls'
  ;
  RAISE DEBUG 'search_path changed to %', current_setting('search_path');
END
$$;

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

-- Schema already created via CREATE EXTENSION
GRANT USAGE ON SCHEMA object_reference TO object_reference__usage;
CREATE SCHEMA _object_reference;

CREATE TABLE _object_reference.object(
  object_id       serial                  PRIMARY KEY
  , object_type   cat_tools.object_type   NOT NULL
  , classid       oid                     NOT NULL
    CONSTRAINT classid_must_match__object__address_classid
      CHECK( classid IS NOT DISTINCT FROM cat_tools.object__address_classid(object_type) )
  , objid         oid                     NOT NULL
    CONSTRAINT objid_must_match CHECK(
      objid IS NOT DISTINCT FROM coalesce(
  regclass::oid -- Need to cast first item to generic OID
  , regconfig
  , regdictionary
  , regnamespace -- SED: REQUIRES 9.5!
  , regoperator
  , regprocedure
  , regtype
  , object_oid
      )
    )
  , objsubid      int                     NOT NULL
  , CONSTRAINT object__u_classid__objid__objsubid UNIQUE( classid, objid, objsubid )
--  , original_name text                    NOT NULL
  , regclass      regclass
    CONSTRAINT regclass_classid CHECK( regclass IS NULL OR classid = cat_tools.object__reg_type_catalog('regclass') )
  , regconfig     regconfig
    CONSTRAINT regconfig_classid CHECK( regconfig IS NULL OR classid = cat_tools.object__reg_type_catalog('regconfig') )
  , regdictionary regdictionary
    CONSTRAINT regdictionary_classid CHECK( regdictionary IS NULL OR classid = cat_tools.object__reg_type_catalog('regdictionary') )
  , regnamespace  regnamespace -- SED: REQUIRES 9.5!
    CONSTRAINT regnamespace_classid CHECK( regnamespace IS NULL OR classid = cat_tools.object__reg_type_catalog('regnamespace') ) -- SED: REQUIRES 9.5!
  , regoperator   regoperator
    CONSTRAINT regoperator_classid CHECK( regoperator IS NULL OR classid = cat_tools.object__reg_type_catalog('regoperator') )
  , regprocedure  regprocedure
    CONSTRAINT regprocedure_classid CHECK( regprocedure IS NULL OR classid = cat_tools.object__reg_type_catalog('regprocedure') )
  -- I don't think we should ever have regrole since we can't create event triggers on it
--  , regrole       regrole
  , regtype       regtype
    CONSTRAINT regtype_classid CHECK( regtype IS NULL OR classid = cat_tools.object__reg_type_catalog('regtype') )
  , object_oid    oid
  , object_names text[]                  NOT NULL
  , object_args  text[]                  NOT NULL
  , CONSTRAINT object__u_object_names__object_args UNIQUE( object_type, object_names, object_args )
  , CONSTRAINT object__address_sanity
    -- pg_get_object_address will throw an error if anything is wrong, so the IS NOT NULL is mostly pointless
    CHECK( pg_catalog.pg_get_object_address(object_type::text, object_names, object_args) IS NOT NULL )
);
CREATE TRIGGER null_count
  AFTER INSERT OR UPDATE
  ON _object_reference.object
  FOR EACH ROW EXECUTE PROCEDURE not_null_count_trigger(
    8 -- First 5 fields, identifier field, object_* fields (can't do actual addition here)
    , 'only one object reference field may be set'
  )
;
CREATE UNIQUE INDEX object__u_regclass ON _object_reference.object(regclass) WHERE regclass IS NOT NULL;
CREATE UNIQUE INDEX object__u_regconfig ON _object_reference.object(regconfig) WHERE regconfig IS NOT NULL;
CREATE UNIQUE INDEX object__u_regdictionary ON _object_reference.object(regdictionary) WHERE regdictionary IS NOT NULL;
CREATE UNIQUE INDEX object__u_regoperator ON _object_reference.object(regoperator) WHERE regoperator IS NOT NULL;
CREATE UNIQUE INDEX object__u_regprocedure ON _object_reference.object(regprocedure) WHERE regprocedure IS NOT NULL;
CREATE UNIQUE INDEX object__u_regtype ON _object_reference.object(regtype) WHERE regtype IS NOT NULL;


/*
 * OBJECT GROUP
 */

CREATE TABLE _object_reference.object_group(
  object_group_id         serial        PRIMARY KEY
  , object_group_name     varchar(200)  NOT NULL
);
CREATE UNIQUE INDEX object_group__u_object_group_name__lower ON _object_reference.object_group(lower(object_group_name));

CREATE TABLE _object_reference.object_group__object(
  object_group_id         int     NOT NULL REFERENCES _object_reference.object_group
  , object_id             int     NOT NULL REFERENCES _object_reference.object
  , CONSTRAINT object_group__object__u_object_group_id__object_id UNIQUE( object_group_id, object_id )
);

-- __get
CREATE FUNCTION object_reference.object_group__get(
  object_group_name _object_reference.object_group.object_group_name%TYPE
) RETURNS _object_reference.object_group LANGUAGE plpgsql STABLE AS $body$
DECLARE
  r _object_reference.object_group;
BEGIN
  SELECT INTO STRICT r
    *
    FROM _object_reference.object_group ogo
    WHERE lower(ogo.object_group_name) = lower(object_group__get.object_group_name)
  ;
  RETURN r;
EXCEPTION WHEN no_data_found THEN
  RAISE 'object group "%" does not exist', object_group_name
    USING ERRCODE = 'no_data_found'
  ;
END
$body$;
CREATE FUNCTION object_reference.object_group__get(
  object_group_id _object_reference.object_group.object_group_id%TYPE
) RETURNS _object_reference.object_group LANGUAGE plpgsql STABLE AS $body$
DECLARE
  r _object_reference.object_group;
BEGIN
  SELECT INTO STRICT r
    *
    FROM _object_reference.object_group ogo
    WHERE (ogo.object_group_id) = (object_group__get.object_group_id)
  ;
  RETURN r;
EXCEPTION WHEN no_data_found THEN
  RAISE 'object group id % does not exist', object_group_id
    USING ERRCODE = 'no_data_found'
  ;
END
$body$;

-- __create
CREATE FUNCTION object_reference.object_group__create(
  object_group_name _object_reference.object_group.object_group_name%TYPE
) RETURNS int LANGUAGE sql AS $body$
INSERT INTO _object_reference.object_group(object_group_name) VALUES(object_group_name)
  RETURNING object_group_id
$body$;

-- __remove
CREATE FUNCTION object_reference.object_group__remove(
  object_group_id _object_reference.object_group.object_group_id%TYPE
) RETURNS void LANGUAGE sql AS $body$
DELETE FROM _object_reference.object_group
  -- This is to ensure group exists
  WHERE object_group_id = (object_reference.object_group__get($1)).object_group_id
$body$;
CREATE FUNCTION object_reference.object_group__remove(
  object_group_name _object_reference.object_group.object_group_name%TYPE
) RETURNS void LANGUAGE sql AS $body$
DELETE FROM _object_reference.object_group
  -- This is to ensure group exists
  WHERE object_group_name = (object_reference.object_group__get($1)).object_group_name
$body$;

-- __object__add
CREATE FUNCTION object_reference.object_group__object__add(
  object_group_id _object_reference.object_group__object.object_group_id%TYPE
  , object_id _object_reference.object_group__object.object_id%TYPE
) RETURNS void LANGUAGE sql AS $body$
  INSERT INTO _object_reference.object_group__object AS ogo(object_group_id, object_id)
    VALUES($1, $2)
    ON CONFLICT (object_group_id, object_id) DO NOTHING
$body$;

-- __object__remove
CREATE FUNCTION object_reference.object_group__object__remove(
  object_group_id _object_reference.object_group__object.object_group_id%TYPE
  , object_id _object_reference.object_group__object.object_id%TYPE
) RETURNS void LANGUAGE plpgsql AS $body$
BEGIN
  DELETE FROM _object_reference.object_group__object AS ogo
    WHERE
      (
        ogo.object_group_id
        , ogo.object_id
      ) = (
        -- This is to ensure group exists
        (object_reference.object_group__get($1)).object_group_id
        , object_group__object__remove.object_id
      )
  ;

  IF NOT FOUND THEN
    -- We know group exists, so issue must be that object doesn't exist
    RAISE 'object id % does not exist', object_id
      USING ERRCODE = 'no_data_found'
    ;
  END IF;
END
$body$;


/*
 * OBJECT GETSERT
 */
CREATE FUNCTION _object_reference.object__getsert(
  object_type _object_reference.object.object_type%TYPE
  , objid _object_reference.object.objid%TYPE
  , objsubid _object_reference.object.objsubid%TYPE
  , object_group_id int DEFAULT NULL
) RETURNS _object_reference.object LANGUAGE plpgsql AS $body$
DECLARE
  c_reg_type name := cat_tools.object__reg_type(object_type); -- Verifies regtype is supported, if there is one
  c_classid CONSTANT regclass := cat_tools.object__address_classid(object_type);
  c_oid_field CONSTANT name := coalesce(c_reg_type, 'object_oid');

  c_insert CONSTANT text := format(
    -- USING object_type, c_classid, objid, objsubid, object_names, object_args
      $$INSERT INTO _object_reference.object(object_type, classid, objid, objsubid, %I, object_names, object_args)
          SELECT $1, $2, $3, $4, $3::%I, $5, $6
        RETURNING *$$
      , c_oid_field
      , coalesce(c_reg_type, 'oid')
    )
  ;

  r_object _object_reference.object;
  r_address record;

  i smallint;
  sql text;
BEGIN
  -- TODO: throw exception for unsupported object types (shared objects such as roles and databases)

  SELECT INTO r_address * FROM pg_catalog.pg_identify_object_as_address(c_classid, objid, objsubid);

  IF r_address IS NULL THEN
    RAISE 'unable to find object'
      USING DETAIL = format(
        'pg_identify_object_as_address(%s, %s, %s) returned NULL'
        , c_classid
        , objid
        , objsubid
      )
    ;
  END IF;

  FOR i IN 1..10 LOOP
    SELECT INTO r_object
        *
      FROM _object_reference.object o
      WHERE (o.classid, o.objid, o.objsubid) = (c_classid, object__getsert.objid, object__getsert.objsubid)
      FOR KEY SHARE
    ;
    IF FOUND THEN
      IF object_group_id IS NOT NULL THEN
        PERFORM object_reference.object_group__object__add(object_group_id, r_object.object_id);
      END IF;
      RETURN r_object;
    END IF;

    BEGIN
      EXECUTE c_insert
        INTO r_object
        USING object_type, c_classid, objid, objsubid, r_address.object_names, r_address.object_args
      ;

      IF object_group_id IS NOT NULL THEN
        PERFORM object_reference.object_group__object__add(object_group_id, r_object.object_id);
      END IF;
      RETURN r_object;
    EXCEPTION WHEN unique_violation THEN
      NULL;
    END;
  END LOOP;

  RAISE 'fell out of loop!' USING HINT = 'This should never happen.';
END
$body$;

CREATE FUNCTION object_reference.object__getsert_w_group_id(
  object_type   cat_tools.object_type
  , object_name text
  , secondary text DEFAULT NULL
  , object_group_id int DEFAULT NULL
) RETURNS int LANGUAGE plpgsql AS $body$
DECLARE
  c_catalog CONSTANT regclass := cat_tools.object__catalog(object_type);

  v_objid oid;
  v_subid int := 0;
BEGIN
  -- Some catalogs need special handling
  CASE c_catalog
  -- Functions
  WHEN 'pg_catalog.pg_proc'::regclass THEN
    /*
     * Need to handle functions specially to support all the extra options they
     * can have that regprocedure doesn't support.
     */
    -- TODO: allow this to parse object_name directly
    v_objid := cat_tools.regprocedure(object_name, secondary);
    secondary = NULL;

  -- Columns
  WHEN 'pg_catalog.pg_attribute'::regclass THEN
    -- Will throw error if column isn't valid
    v_objid := object_name::regclass;
    v_subid := (cat_tools.pg_attribute__get(v_objid, secondary)).attnum;
    secondary = NULL;

  ELSE
    DECLARE
      c_reg_type name := cat_tools.object__reg_type(c_catalog);

      v_name_field text;
      sql text;
    BEGIN
      IF c_reg_type IS NULL THEN
        /*
         * Need to do a manual lookup of the OID based on what catalog it is
         *
         * Get first 3 letters of catalog name after the 'pg_', since that's
         * usually the field name. We also need to handle the possibility of
         * 'pg_catalog.' being part of c_catalog.
         */
        v_name_field := substring(regexp_replace(c_catalog::text, '(pg_catalog\.)?pg_', ''), 1, 3);

        v_name_field := CASE v_name_field
            WHEN 'tri' THEN 'tg' -- pg_trigger
            ELSE v_name_field
          END || 'name'
        ;
        sql := format(
          'SELECT oid FROM %s WHERE %I = %L'
          , c_catalog -- No need to quote
          , v_name_field
          , object_name
        );
      ELSE
        sql := format(
          'SELECT %L::%s'
          , object_name
          , c_reg_type -- No need to quote
        );
      END IF;
      EXECUTE sql INTO STRICT v_objid;
    END;
  END CASE;

  IF secondary IS NOT NULL THEN
    RAISE 'secondary may not be specified for % objects', object_type;
  END IF;

  RETURN (_object_reference.object__getsert( object_type, v_objid, v_subid, object_group_id )).object_id;
END
$body$;

CREATE FUNCTION object_reference.object__getsert(
  object_type   cat_tools.object_type
  , object_name text
  , secondary text DEFAULT NULL
  , object_group_name _object_reference.object_group.object_group_name%TYPE DEFAULT NULL
) RETURNS int LANGUAGE sql AS $body$
SELECT object_reference.object__getsert_w_group_id(
  $1, $2, $3
  , CASE WHEN object_group_name IS NOT NULL THEN
      (object_reference.object_group__get($4)).object_group_id
    END
)
$body$;

CREATE FUNCTION _object_reference._etg_fix_identity(
) RETURNS event_trigger LANGUAGE plpgsql AS $body$
DECLARE
  r_ddl record;
  r record;
BEGIN
  /*
   * It's tempting to use pg_event_trigger_ddl_commands() to find exactly what
   * items have changed and worry about only those. That won't work because an
   * object_names array can depend on multiple names (ie: a column depends on
   * the name of it's table, as well as the name of the schema the table is in.
   * You might think we could simply recurse through pg_depend to handle this,
   * but not every name dependency gets enumerated that way. For example,
   * columns are not marked as dependent on their table.
   *
   * Rather than trying to be cute about this, we just do a brute-force check
   * for any names that have changed.
   */

  /*
   * Presumably there's no way for an objects type/classid to change, but be
   * safe and attempt the update to object_type. If it actually does change the
   * constraint on the table should catch it.
   */
  FOR r IN
    UPDATE _object_reference.object
      SET object_type  = (pg_catalog.pg_identify_object_as_address(classid, objid, objsubid)).type::cat_tools.object_type
        , object_names = (pg_catalog.pg_identify_object_as_address(classid, objid, objsubid)).object_names
        , object_args  = (pg_catalog.pg_identify_object_as_address(classid, objid, objsubid)).object_args
      WHERE (object_type::text, object_names, object_args) IS DISTINCT FROM
        (pg_catalog.pg_identify_object_as_address(classid, objid, objsubid))
      RETURNING *
  LOOP
    RAISE DEBUG 'modified_objects(): %', r;
  END LOOP;
END
$body$;
CREATE FUNCTION _object_reference._etg_drop(
) RETURNS event_trigger LANGUAGE plpgsql AS $body$
DECLARE
  r_object _object_reference.object;
  r record;
BEGIN
  FOR r IN SELECT classid, objid, objsubid, object_type, schema_name, object_identity FROM pg_catalog.pg_event_trigger_dropped_objects() LOOP
    RAISE DEBUG 'dropped_objects(): %', r;
  END LOOP;
  -- Multiple objects might have been affected
  -- Could potentially be done with a writable CTE
  FOR r_object IN
    SELECT object.*
      FROM pg_catalog.pg_event_trigger_dropped_objects() d
        JOIN _object_reference.object USING( classid, objid ) -- Intentionally ignore objsubid
      WHERE
        /*
         * If an object that contains subobjects is being removed, we need to
         * also remove all subobjects. Otherwise, only remove the appropriate
         * suboject.
         */
        d.objsubid = 0 -- Case 1 above (or object doesn't have subobjects, which is fine)
        OR d.objsubid = object.objsubid
  LOOP
    RAISE DEBUG 'deleting object %', r_object;
    -- TODO: trap FK violation error on groups and output something better
    DELETE FROM _object_reference.object WHERE object_id = r_object.object_id;
  END LOOP;
END
$body$;

CREATE EVENT TRIGGER zzz__object_reference_drop
  ON sql_drop
  -- For debugging
  --WHEN tag IN ( 'ALTER TABLE', 'DROP TABLE' )
  EXECUTE PROCEDURE _object_reference._etg_drop()
;
CREATE EVENT TRIGGER zzz_object_reference_end
  ON ddl_command_end
  -- For debugging
  --WHEN tag IN ( 'ALTER TABLE', 'DROP TABLE' )
  EXECUTE PROCEDURE _object_reference._etg_fix_identity()
;

/*
 * Drop "temporary" objects
 */
DROP FUNCTION __object_reference.exec(
  sql text
);
DROP SCHEMA __object_reference;

-- vi: expandtab sw=2 ts=2
