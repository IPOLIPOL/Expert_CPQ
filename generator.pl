/*=============================================================================
  Diesel Generator Expert Configurator
  SWI-Prolog — Single-file version

  ARCHITECTURE — four strictly isolated layers
  =============================================

    ┌──────────────────────────────────────────────────────────────┐
    │  LAYER 4 — PRESENTATION                                      │
    │  print_bom_tree/2, print_service_tree/2, help_menu/0         │
    │  Receives opaque Config and bom_node/4 terms.                │
    │  Calls ONLY Layer 2 interfaces. Knows no parameter names,    │
    │  no component names, no ontology predicates.                 │
    ├──────────────────────────────────────────────────────────────┤
    │  LAYER 3 — QUERY / CLI                                       │
    │  list_*, count_*, print_config_summary/2                     │
    │  Calls ONLY Layer 2 interfaces. Formats results for display. │
    ├──────────────────────────────────────────────────────────────┤
    │  LAYER 2 — REASONING                                         │
    │  product_variant/2, config_bom/3, config_price/3             │
    │  service_variant/4, service_scope_price/3                    │
    │  Pure logic. Calls ONLY Layer 1 predicates.                  │
    │  Single access point to Config values: config_get/3.         │
    ├──────────────────────────────────────────────────────────────┤
    │  LAYER 1 — ONTOLOGY                                          │
    │  Facts only. No procedural logic.                            │
    │  product/1  product_parameters/2  parameter_values/2         │
    │  compatibility_rule/2  compatibility_holds/2                 │
    │  product_structure/2  component/3                            │
    │  service_parameter_values/3  service_item/3                  │
    └──────────────────────────────────────────────────────────────┘

  CONFIGURATION REPRESENTATION
  ============================

  A product configuration is an opaque pair-list:

      Config = [apparent_power-kva_400, voltage-v_400, frequency-hz_50,
                emission-eu_stage_5, certification-ce]

  THE ONLY WAY to read a value from Config outside Layer 1 is:

      config_get(+Config, +ParameterName, -Value)

  This means:
    - The reasoner never mentions 'emission', 'voltage', etc. by name.
    - The printer never mentions parameter names.
    - Adding/removing a parameter touches ONLY Layer 1 facts.
    - To swap pair-list for library(assoc) when parameters grow past ~15:
      change config_get/3 only. Zero other changes required.

  EXTENDING THE SYSTEM
  ====================

  Add a parameter:
    1. Append atom to product_parameters/2 list            [Layer 1]
    2. Add parameter_values/2 fact                         [Layer 1]
    3. Add compatibility_rule/2 + compatibility_holds/2    [Layer 1, if needed]
    → Zero changes in Layers 2, 3, 4.

  Add a component:
    1. Add comp{} entry to product_structure/2             [Layer 1]
    2. Add component/3 fact(s)                             [Layer 1]
    → Zero changes in Layers 2, 3, 4.

  Add a service item:
    1. Add service_parameter_values/3 facts                [Layer 1]
    2. Add service_item/3 fact(s)                          [Layer 1]
    → Zero changes in Layers 2, 3, 4.

  CLI usage:
    swipl generator.pl
    ?- help_menu.
    ?- list_variants_with_count(diesel_generator).
    ?- print_bom_tree(diesel_generator,
           [apparent_power-kva_400, voltage-v_400, frequency-hz_50,
            emission-eu_stage_5, certification-ce]).
    ?- print_service_tree(
           [genset_service-standard, scr_service-extended,
            commissioning-full, warranty-warranty_5yr], eu_stage_5).
    ?- validate_ontology.


    chcp 65001  — Windows can't display the ASCII diagrams properly.
                  Run that in your terminal before anything else. 
                  It switches the Windows console to UTF-8. Then rebuild.
=============================================================================*/

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module(generator_graphics).

/*=============================================================================
  LAYER 1 — ONTOLOGY
  Facts only. The only calls allowed here are to other Layer 1 facts,
  specifically in compatibility_holds/2 which calls the compatible_vf/2
  and compatible_ec/2 facts, and config_get/3. No iteration, no findall.
=============================================================================*/

/*-----------------------------------------------------------------------------
  1.1  Product catalogue
-----------------------------------------------------------------------------*/

product(diesel_generator).

% product_parameters(+Product, -Params)
% Ordered list — determines the order of pairs in every Config list.
product_parameters(diesel_generator, [
    placement,
    application_type,
    apparent_power,
    lv_connection,
    voltage,
    frequency,
    emission,
    routine_test,
    certification,
    daytank_init_fill,
    def_daytank_init_fill
]).

/*-----------------------------------------------------------------------------
  1.2  Parameter domains
  To add a value: extend the list. Nothing else changes anywhere.
-----------------------------------------------------------------------------*/
parameter_values(placement,         [indoor, outdoor]).
parameter_values(application_type,  [industrial, marine]).
parameter_values(apparent_power,    [kva_250, kva_400, kva_560]).
parameter_values(lv_connection,     [single, double]).
parameter_values(voltage,           [v_400, v_480]).
parameter_values(frequency,         [hz_50, hz_60]).
parameter_values(emission,          [eu_stage_5, eu_stage_3, epa_tier_4, imo_tier_3]).
parameter_values(routine_test,      [grid, load_bank]).
parameter_values(certification,     [dnv, ce, ul, none]).
parameter_values(daytank_init_fill, [empty, full]).
parameter_values(def_daytank_init_fill, [empty, full]).

/*-----------------------------------------------------------------------------
  1.3  Compatibility rules

  Two-part declaration keeps domain knowledge in Layer 1:

  Part A: compatibility_rule(Product, RuleName)
    Registers which rules apply to a product.
    Add a new rule: add a fact here + a compatibility_holds/2 clause.

  Part B: compatibility_holds(RuleName, Config)
    What "satisfied" means for each named rule.
    Uses config_get/3 — the ONLY sanctioned way to read Config.
    This is Layer 1 because it encodes domain knowledge (which values
    may coexist), not algorithmic iteration.

  Raw compatible_vf/2 and compatible_ec/2 facts are private to this section.
-----------------------------------------------------------------------------*/

compatibility_rule(diesel_generator, voltage_frequency).
compatibility_rule(diesel_generator, emission_certification).
compatibility_rule(diesel_generator, emission_application_type).

compatibility_holds(voltage_frequency, Config) :-
    config_get(Config, voltage,   V),
    config_get(Config, frequency, F),
    compatible_voltage_frequency(V, F).

compatibility_holds(emission_certification, Config) :-
    config_get(Config, emission,      E),
    config_get(Config, certification, C),
    compatible_emission_certification(E, C).

compatibility_holds(emission_application_type, Config) :-
    config_get(Config, emission,      E),
    config_get(Config, application_type, AT),
    compatible_emission_application_type(E, AT).

% 480 V is only valid at 60 Hz; 400 V allows both.
compatible_voltage_frequency(v_400, hz_50).
compatible_voltage_frequency(v_400, hz_60).
compatible_voltage_frequency(v_480, hz_60).

compatible_emission_certification(eu_stage_5, dnv).
compatible_emission_certification(eu_stage_5, ce).
compatible_emission_certification(eu_stage_5, none).
compatible_emission_certification(eu_stage_3, dnv).
compatible_emission_certification(eu_stage_3, ce).
compatible_emission_certification(eu_stage_3, none).
compatible_emission_certification(epa_tier_4, ul).
compatible_emission_certification(epa_tier_4, none).
compatible_emission_certification(imo_tier_3, dnv).
compatible_emission_certification(imo_tier_3, ce).
compatible_emission_certification(imo_tier_3, none).
compatible_emission_certification(imo_tier_3, ul).

compatible_emission_application_type(eu_stage_5, industrial).
compatible_emission_application_type(eu_stage_3, industrial).
compatible_emission_application_type(epa_tier_4, industrial).
compatible_emission_application_type(imo_tier_3, marine).

/*-----------------------------------------------------------------------------
  1.4  Product structure

  comp{} dict fields:
    name      — atom; must match a component/3 entry
    mandatory — true | false
    requires  — none
                param(ParameterName, [AllowedValues])
                  include this component only when the named parameter's
                  value is in the allowed list

  To extend: add a comp{} entry here + component/3 facts below.
-----------------------------------------------------------------------------*/

product_structure(diesel_generator, [
    comp{name: genset,                  mandatory: true,  requires: none},
    comp{name: electrical_cabinet,      mandatory: true,  requires: none},
    comp{name: daytank,                 mandatory: true,  requires: none},
    comp{name: battery,                 mandatory: true,  requires: none},
    comp{name: battery_charger,         mandatory: true,  requires: none},
    comp{name: air_intake,              mandatory: true,  requires: none},
    comp{name: air_outlet,              mandatory: true,  requires: none},
    comp{name: inner_exhaust_piping,    mandatory: true,  requires: none},
    comp{name: outer_exhaust_piping,    mandatory: true,  requires: none},
    comp{name: muffler,                 mandatory: true,  requires: none},
    comp{name: scr_unit,                mandatory: false,
         requires: param(emission, [eu_stage_5, epa_tier_4, imo_tier_3])},
    comp{name: def_main_tank,           mandatory: false,
         requires: param(emission, [eu_stage_5, epa_tier_4, imo_tier_3])},
    comp{name: def_day_tank,            mandatory: false,
         requires: param(emission, [eu_stage_5, epa_tier_4, imo_tier_3])},
    comp{name: def_pump,                mandatory: false,
         requires: param(emission, [eu_stage_5, epa_tier_4, imo_tier_3])},
    comp{name: containerized_enclosure, mandatory: false, requires: none}
]).

/*-----------------------------------------------------------------------------
  1.5  Component definitions

  component(Product, ComponentName, component{...})

  used_in field — a list of match specs, each one of:
    any           matches every config
    v(Power,Freq) matches specific apparent_power + frequency values
    EmissionAtom  matches a specific emission parameter value

  To add a variant: add a component/3 fact. Nothing else changes.
-----------------------------------------------------------------------------*/

% --- GENSET ------------------------------------------------------------------

component(diesel_generator, genset, component{
    used_in: [v(kva_250, hz_50)], type: rotating_equipment,
    quantity: 1, replaceable: true, vendor: 'ABZ', article: 'TAD1-250-50',
    rating_ISO_8528: 'PRP', cosphi: 0.8, 
    active_power: kw_200, rotating_speed: rpm_1500,
    price_dkk: 400000, service_interval_hours: 500,
    sub_components: [engine, alternator, base_frame, speed_governor,
                     avr, excitation_system, cooling_system, lubrication_system]
}).
component(diesel_generator, genset, component{
    used_in: [v(kva_250, hz_60)], type: rotating_equipment,
    quantity: 1, replaceable: true, vendor: 'ABZ', article: 'TAD1-250-60',
    rating_ISO_8528: 'PRP', cosphi: 0.8, 
    active_power: kw_200,rotating_speed: rpm_1800,
    price_dkk: 420000, service_interval_hours: 500,
    sub_components: [engine, alternator, base_frame, speed_governor,
                     avr, excitation_system, cooling_system, lubrication_system]
}).
component(diesel_generator, genset, component{
    used_in: [v(kva_400, hz_50)], type: rotating_equipment,
    quantity: 1, replaceable: true, vendor: 'ABZ', article: 'TAD2-400-50',
    rating_ISO_8528: 'PRP', cosphi: 0.8, 
    active_power: kw_320, rotating_speed: rpm_1500,
    price_dkk: 550000, service_interval_hours: 500,
    sub_components: [engine, alternator, base_frame, speed_governor,
                     avr, excitation_system, cooling_system, lubrication_system]
}).
component(diesel_generator, genset, component{
    used_in: [v(kva_400, hz_60)], type: rotating_equipment,
    quantity: 1, replaceable: true, vendor: 'ABZ', article: 'TAD2-400-60',
    rating_ISO_8528: 'PRP', cosphi: 0.8, 
    active_power: kw_320, rotating_speed: rpm_1800,
    price_dkk: 550000, service_interval_hours: 500,
    sub_components: [engine, alternator, base_frame, speed_governor,
                     avr, excitation_system, cooling_system, lubrication_system]
}).
component(diesel_generator, genset, component{
    used_in: [v(kva_560, hz_50)], type: rotating_equipment,
    quantity: 1, replaceable: true, vendor: 'ABZ', article: 'TAD2-560-50',
    rating_ISO_8528: 'PRP', cosphi: 0.8, 
    active_power: kw_448, rotating_speed: rpm_1500,
    price_dkk: 600000, service_interval_hours: 500,
    sub_components: [engine, alternator, base_frame, speed_governor,
                     avr, excitation_system, cooling_system, lubrication_system]
}).
component(diesel_generator, genset, component{
    used_in: [v(kva_560, hz_60)], type: rotating_equipment,
    quantity: 1, replaceable: true, vendor: 'ABZ', article: 'TAD2-560-60',
    rating_ISO_8528: 'PRP', cosphi: 0.8, 
    active_power: kw_448, rotating_speed: rpm_1800,
    price_dkk: 600000, service_interval_hours: 500,
    sub_components: [engine, alternator, base_frame, speed_governor,
                     avr, excitation_system, cooling_system, lubrication_system]
}).

% --- ELECTRICAL CABINET ------------------------------------------------------

component(diesel_generator, electrical_cabinet, component{
    used_in: [any], type: cabinet,
    quantity: 1, replaceable: true, vendor: 'HPS', article: 'HPA-01',
    price_dkk: 320000, service_interval_hours: 10000,
    sub_components: [plc, circuit_breakers, bus_bars,
                     control_panel, relay_protection]
}).

% --- DAYTANK -----------------------------------------------------------------

component(diesel_generator, daytank, component{
    used_in: [any], type: static_equipment,
    quantity: 1, replaceable: true, vendor: 'ABZ', article: 'DT-500',
    autonomy_hours: 18,
    price_dkk: 45000, service_interval_hours: 8000,
    sub_components: [fuel_level_sensor, overflow_valve, fill_pump]
}).

% --- BATTERY (quantity = 2) --------------------------------------------------

component(diesel_generator, battery, component{
    used_in: [any], type: minor,
    quantity: 2, replaceable: true, vendor: 'Varta', article: 'VARTA-AGM-12V',
    price_dkk: 4500, service_interval_hours: 8000
}).

% --- BATTERY CHARGER (quantity = 2) ------------------------------------------

component(diesel_generator, battery_charger, component{
    used_in: [any], type: minor,
    quantity: 2, replaceable: true, vendor: 'Victron', article: 'VICTRON-BC-12V',
    price_dkk: 3500, service_interval_hours: 8000
}).

% --- AIR HANDLING ------------------------------------------------------------

component(diesel_generator, air_intake, component{
    used_in: [any], type: air_flow,
    quantity: 1, replaceable: true, vendor: 'Lowara', article: 'LOWARA-AIR-INTAKE',
    price_dkk: 45000, service_interval_hours: 8000,
    sub_components: [intake_filter, intake_damper, intake_louvre]
}).
component(diesel_generator, air_outlet, component{
    used_in: [any], type: air_flow,
    quantity: 1, replaceable: true, vendor: 'Lowara', article: 'LOWARA-AIR-OUTLET',
    price_dkk: 45000, service_interval_hours: 8000,
    sub_components: [outlet_damper, outlet_louvre]
}).

% --- EXHAUST -----------------------------------------------------------------

component(diesel_generator, inner_exhaust_piping, component{
    used_in: [any], type: static_equipment,
    quantity: 1, replaceable: true, vendor: 'Burgess', article: 'BMI-440',
    price_dkk: 8000, service_interval_hours: 10000
}).
component(diesel_generator, outer_exhaust_piping, component{
    used_in: [any], type: static_equipment,
    quantity: 1, replaceable: true, vendor: 'Burgess', article: 'BME-440',
    price_dkk: 8000, service_interval_hours: 10000
}).
component(diesel_generator, muffler, component{
    used_in: [any], type: static_equipment,
    quantity: 1, replaceable: true, vendor: 'Burgess', article: 'BM-440',
    price_dkk: 8000, service_interval_hours: 10000
}).

% --- DEF SYSTEM --------------------------------------------------------------

component(diesel_generator, scr_unit, component{
    used_in: [any], type: static_equipment,
    quantity: 1, replaceable: true, vendor: 'Dinex', article: 'SCR-220',
    price_dkk: 45000, service_interval_hours: 8000,
    sub_components: [catalyst, temperature_sensor, nox_sensor]
}).

component(diesel_generator, def_main_tank, component{
    used_in: [any], type: static_equipment,
    quantity: 1, replaceable: true, vendor: 'Dinex', article: 'DEF-220',
    price_dkk: 45000, service_interval_hours: 8000,
    sub_components: [level_sensor, heating_element]
}).
component(diesel_generator, def_day_tank, component{
    used_in: [any], type: static_equipment,
    quantity: 1, replaceable: true, vendor: 'Dinex', article: 'DEF-230',
    price_dkk: 12000, service_interval_hours: 8000
}).
component(diesel_generator, def_pump, component{
    used_in: [any], type: static_equipment,
    quantity: 1, replaceable: true, vendor: 'Dinex', article: 'DEF-240',
    price_dkk: 18000, service_interval_hours: 8000,
    sub_components: [pump_motor, dosing_valve, strainer]
}).

% --- CONTAINERIZED ENCLOSURE -------------------------------------------------

component(diesel_generator, containerized_enclosure, component{
    used_in: [eu_stage_5, epa_tier_4, imo_tier_3], type: structural,
    quantity: 1, replaceable: false, vendor: 'ABZ', article: 'ENCL-01',
    price_dkk: 2800000, service_interval_hours: 30000,
    sub_components: [ventilation_inlet, ventilation_outlet,
                     cable_penetration, access_door]
}).
component(diesel_generator, containerized_enclosure, component{
    used_in: [eu_stage_3], type: structural,
    quantity: 1, replaceable: false, vendor: 'ABZ', article: 'ENCL-02',
    price_dkk: 2200000, service_interval_hours: 30000,
    sub_components: [ventilation_inlet, ventilation_outlet,
                     cable_penetration, access_door]
}).

/*-----------------------------------------------------------------------------
  1.6  Service parameter domains

  service_parameter_values(ItemName, variant, [Keys])
    Closed set of variant/tier keys for each service item.

  service_parameter_values(emission, [Values])
    Emission contexts recognised in the service domain.
    Mirrors the product emission domain.
-----------------------------------------------------------------------------*/

service_parameter_values(emission, [eu_stage_5, eu_stage_3, epa_tier_4, any]).

service_parameter_values(genset_service,    variant, [standard, extended, premium]).
service_parameter_values(cabinet_service,   variant, [standard, extended]).
service_parameter_values(daytank_service,   variant, [standard]).
service_parameter_values(battery_service,   variant, [standard]).
service_parameter_values(exhaust_service,   variant, [standard]).
service_parameter_values(scr_service,       variant, [standard, extended]).
service_parameter_values(def_service,       variant, [standard]).
service_parameter_values(commissioning,     variant, [basic, full]).
service_parameter_values(warranty,          variant, [warranty_2yr, warranty_5yr]).
service_parameter_values(remote_monitoring, variant, [basic, advanced]).

/*-----------------------------------------------------------------------------
  1.7  Service item definitions

  service_item(ItemName, VariantKey, service{...})

  Dict fields:
    description — human-readable label
    applies_to  — [any] | [EmissionAtom, ...]
    price_dkk   — fixed price
    interval    — hours (0 = one-time)
    sub_items   — [atom, ...]  task list shown in tree
-----------------------------------------------------------------------------*/

service_item(genset_service, standard, service{
    description: 'Genset standard service (500 h)',
    applies_to: [any], price_dkk: 18000, interval: 500,
    sub_items: [oil_change, oil_filter, fuel_filter,
                air_filter, belt_inspection, coolant_check]
}).
service_item(genset_service, extended, service{
    description: 'Genset extended service (incl. injector test)',
    applies_to: [any], price_dkk: 28000, interval: 500,
    sub_items: [oil_change, oil_filter, fuel_filter, air_filter,
                belt_inspection, coolant_check,
                injector_test, compression_test]
}).
service_item(genset_service, premium, service{
    description: 'Genset premium service (full overhaul)',
    applies_to: [any], price_dkk: 48000, interval: 1000,
    sub_items: [oil_change, oil_filter, fuel_filter, air_filter,
                belt_replacement, coolant_flush,
                injector_test, compression_test,
                thermostat_replacement, hose_inspection]
}).

service_item(cabinet_service, standard, service{
    description: 'Cabinet standard service',
    applies_to: [any], price_dkk: 8000, interval: 8000,
    sub_items: [thermal_scan, relay_test, busbar_torque_check]
}).
service_item(cabinet_service, extended, service{
    description: 'Cabinet extended service (incl. PLC firmware)',
    applies_to: [any], price_dkk: 14000, interval: 8000,
    sub_items: [thermal_scan, relay_test, busbar_torque_check,
                plc_firmware_update, insulation_resistance_test]
}).

service_item(daytank_service, standard, service{
    description: 'Day-tank standard service',
    applies_to: [any], price_dkk: 4500, interval: 8000,
    sub_items: [level_sensor_check, valve_inspection, tank_cleaning]
}).

service_item(battery_service, standard, service{
    description: 'Battery & charger service',
    applies_to: [any], price_dkk: 3500, interval: 8000,
    sub_items: [battery_load_test, terminal_cleaning, charger_output_check]
}).

service_item(exhaust_service, standard, service{
    description: 'Exhaust system inspection',
    applies_to: [any], price_dkk: 5000, interval: 8000,
    sub_items: [flex_joint_check, muffler_inspection, piping_leak_test]
}).

service_item(scr_service, standard, service{
    description: 'SCR standard service',
    applies_to: [eu_stage_5, epa_tier_4], price_dkk: 12000, interval: 4000,
    sub_items: [catalyst_pressure_drop, nox_sensor_calibration,
                temp_sensor_check, dosing_valve_test]
}).
service_item(scr_service, extended, service{
    description: 'SCR extended service (catalyst replacement)',
    applies_to: [eu_stage_5, epa_tier_4], price_dkk: 38000, interval: 8000,
    sub_items: [catalyst_replacement, nox_sensor_replacement,
                temp_sensor_check, dosing_valve_test, system_regeneration]
}).

service_item(def_service, standard, service{
    description: 'DEF system service',
    applies_to: [eu_stage_5, epa_tier_4], price_dkk: 6500, interval: 4000,
    sub_items: [def_pump_inspection, strainer_cleaning,
                level_sensor_check, heating_element_check]
}).

service_item(commissioning, basic, service{
    description: 'Basic commissioning (functional test)',
    applies_to: [any], price_dkk: 22000, interval: 0,
    sub_items: [visual_inspection, load_bank_test_50pct,
                protection_relay_test, handover_documentation]
}).
service_item(commissioning, full, service{
    description: 'Full commissioning (incl. emission & noise tests)',
    applies_to: [eu_stage_5, eu_stage_3, epa_tier_4],
    price_dkk: 45000, interval: 0,
    sub_items: [visual_inspection, load_bank_test_100pct,
                protection_relay_test, emission_measurement,
                noise_measurement, handover_documentation, operator_training]
}).

service_item(warranty, warranty_2yr, service{
    description: '2-year extended warranty',
    applies_to: [any], price_dkk: 35000, interval: 0,
    sub_items: [parts_coverage, labour_coverage]
}).
service_item(warranty, warranty_5yr, service{
    description: '5-year extended warranty',
    applies_to: [any], price_dkk: 75000, interval: 0,
    sub_items: [parts_coverage, labour_coverage, annual_preventive_visit]
}).

service_item(remote_monitoring, basic, service{
    description: 'Remote monitoring — basic (alarms only)',
    applies_to: [any], price_dkk: 12000, interval: 0,
    sub_items: [sim_card_subscription, alarm_forwarding, portal_access]
}).
service_item(remote_monitoring, advanced, service{
    description: 'Remote monitoring — advanced (full telemetry)',
    applies_to: [any], price_dkk: 24000, interval: 0,
    sub_items: [sim_card_subscription, alarm_forwarding, portal_access,
                trend_logging, predictive_maintenance_alerts, annual_report]
}).


/*=============================================================================
  LAYER 2 — REASONING
  Pure logic. Calls ONLY Layer 1 predicates.
  No format/write. No direct calls to component/3, parameter_values/2,
  or product_structure/2 from Layers 3 or 4.
=============================================================================*/

/*-----------------------------------------------------------------------------
  2.0  Config access interface — THE SINGLE SEAM

  config_get(+Config, +Key, -Value)

  This is the ONLY way to read a value from a Config anywhere in the system.
  Config is currently a pair-list: [param1-val1, param2-val2, ...]

  To upgrade to library(assoc) for 20+ parameters:
    Replace the body of this predicate with get_assoc(Key, Config, Value).
    Also update pick_value/2 to build an assoc instead of a pair.
    Zero other changes required anywhere.
-----------------------------------------------------------------------------*/

config_get(Config, Key, Value) :-
    member(Key-Value, Config).

/*-----------------------------------------------------------------------------
  2.1  Variant generator

  product_variant(+Product, -Config)
    Generates all valid configurations for Product via backtracking.
    Config = [Param1-Value1, Param2-Value2, ...] (product_parameters order).

  No parameter names appear in this predicate body.
  It is driven entirely by product_parameters/2, parameter_values/2,
  and compatibility_rule/2 + compatibility_holds/2 from Layer 1.
-----------------------------------------------------------------------------*/

product_variant(Product, Config) :-
    product_parameters(Product, Params),
    maplist(pick_value, Params, Config),
    forall(
        compatibility_rule(Product, Rule),
        compatibility_holds(Rule, Config)
    ).

% pick_value/2 — assigns one value to a parameter (non-deterministic)
pick_value(Param, Param-Value) :-
    parameter_values(Param, Values),
    member(Value, Values).

/*-----------------------------------------------------------------------------
  2.2  BoM resolver

  PUBLIC interface (called by Layers 3 & 4):

    config_bom(+Product, +Config, -BoMNodes)
      BoMNodes = list of bom_node(Name, Article, Qty, Subs)
      Layers 3 & 4 never touch component/3 or product_structure/2 directly.

  PRIVATE helpers (Layer 2 internal):

    active_comps/3      — filter product_structure to active comp{} entries
    comp_active/2       — single comp{} activation check (generic, param-blind)
    resolve_comp/4      — find the matching component dict for this Config
    used_in_matches/2   — match one used_in spec atom/term against Config
-----------------------------------------------------------------------------*/

config_bom(Product, Config, BoMNodes) :-
    product_structure(Product, Structure),
    active_comps(Structure, Config, ActiveComps),
    maplist(comp_to_node(Product, Config), ActiveComps, BoMNodes).

% active_comps/3 — keep only entries whose activation condition holds
active_comps([], _, []).
active_comps([C|Rest], Config, [C|Out]) :-
    comp_active(C, Config), !,
    active_comps(Rest, Config, Out).
active_comps([_|Rest], Config, Out) :-
    active_comps(Rest, Config, Out).

% comp_active/2 — three cases; the param-based case is fully generic:
%   it never names 'emission' — it reads whatever parameter is declared
%   in the requires field of the comp{} dict.
comp_active(Comp, _) :-
    Comp.mandatory = true.
comp_active(Comp, Config) :-
    Comp.mandatory = false,
    Comp.requires  = param(Param, TriggerValues),
    config_get(Config, Param, Value),
    member(Value, TriggerValues).
comp_active(Comp, _) :-
    Comp.mandatory = false,
    Comp.requires  = none.

% comp_to_node/4 — resolve dict and build public bom_node/4 term
comp_to_node(Product, Config, Comp,
             bom_node(Name, Article, Qty, Subs)) :-
    Name = Comp.name,
    resolve_comp(Product, Name, Config, D),
    Article = D.article,
    Qty     = D.quantity,
    ( get_dict(sub_components, D, Subs) -> true ; Subs = [] ).

% resolve_comp/4 — find the component dict whose used_in spec matches Config
resolve_comp(Product, Name, Config, D) :-
    component(Product, Name, D),
    member(Spec, D.used_in),
    used_in_matches(Spec, Config).

% used_in_matches/2 — three spec shapes; reads Config via config_get only
used_in_matches(any, _).
used_in_matches(v(Power, Freq), Config) :-
    config_get(Config, apparent_power, Power),
    config_get(Config, frequency,      Freq).
used_in_matches(EmAtom, Config) :-
    EmAtom \= any,
    EmAtom \= v(_,_),
    config_get(Config, emission, EmAtom).

/*-----------------------------------------------------------------------------
  2.3  Pricing

  config_price(+Product, +Config, -Total)
    Sums price_dkk × quantity for all active BoM components.
    Does NOT use bom_node/4 (which omits price) — resolves component
    dicts directly for pricing, keeping the public BoM interface clean.
-----------------------------------------------------------------------------*/

config_price(Product, Config, Total) :-
    product_structure(Product, Structure),
    active_comps(Structure, Config, ActiveComps),
    findall(LinePrice,
        (   member(Comp, ActiveComps),
            resolve_comp(Product, Comp.name, Config, D),
            LinePrice is D.price_dkk * D.quantity
        ),
        Prices),
    sumlist(Prices, Total).

/*-----------------------------------------------------------------------------
  2.4  Price extremes and sorted list

  cheapest_configs(+Product, -Configs, -MinPrice)
  most_expensive_configs(+Product, -Configs, -MaxPrice)
  all_configs_by_price(+Product, -SortedPairs)
    SortedPairs = [Price-Config, ...] ascending
-----------------------------------------------------------------------------*/

cheapest_configs(Product, Configs, MinPrice) :-
    findall(P-C,
        (product_variant(Product, C), config_price(Product, C, P)),
        Pairs),
    min_member(MinPrice-_, Pairs),
    findall(C, member(MinPrice-C, Pairs), Configs).

most_expensive_configs(Product, Configs, MaxPrice) :-
    findall(P-C,
        (product_variant(Product, C), config_price(Product, C, P)),
        Pairs),
    max_member(MaxPrice-_, Pairs),
    findall(C, member(MaxPrice-C, Pairs), Configs).

all_configs_by_price(Product, Sorted) :-
    findall(P-C,
        (product_variant(Product, C), config_price(Product, C, P)),
        Pairs),
    msort(Pairs, Sorted).

/*-----------------------------------------------------------------------------
  2.5  Service configurator — independent of product Layer 1

  service_item_available(+Item, +VK, +Emission)
  service_variant(+Item, +VK, +Emission, -D)
  all_available_service_variants(+Emission, -Pairs)
  service_cheapest_variant(+Item, +Emission, -VK, -Price)
  service_most_expensive_variant(+Item, +Emission, -VK, -Price)
-----------------------------------------------------------------------------*/

service_item_available(Item, VK, _) :-
    service_item(Item, VK, D), member(any, D.applies_to).
service_item_available(Item, VK, Emission) :-
    service_item(Item, VK, D),
    \+ member(any, D.applies_to),
    member(Emission, D.applies_to).

service_variant(Item, VK, Emission, D) :-
    service_item(Item, VK, D),
    service_item_available(Item, VK, Emission).

all_available_service_variants(Emission, Pairs) :-
    findall(Item-VK,
        (service_item(Item, VK, _), service_item_available(Item, VK, Emission)),
        Pairs).

service_cheapest_variant(Item, Emission, VK, Price) :-
    findall(P-K,
        (   service_parameter_values(Item, variant, Vs), member(K, Vs),
            service_variant(Item, K, Emission, D), P = D.price_dkk ),
        Pairs),
    Pairs \= [], min_member(Price-VK, Pairs).

service_most_expensive_variant(Item, Emission, VK, Price) :-
    findall(P-K,
        (   service_parameter_values(Item, variant, Vs), member(K, Vs),
            service_variant(Item, K, Emission, D), P = D.price_dkk ),
        Pairs),
    Pairs \= [], max_member(Price-VK, Pairs).

/*-----------------------------------------------------------------------------
  2.6  Service pricing

  service_scope_price(+Scope, +Emission, -Total)
    Scope = [ItemName-VariantKey, ...]
    Items unavailable for Emission are silently skipped.
-----------------------------------------------------------------------------*/

service_scope_price(Scope, Emission, Total) :-
    findall(P,
        (member(Item-VK, Scope), service_variant(Item, VK, Emission, D), P = D.price_dkk),
        Prices),
    sumlist(Prices, Total).

/*-----------------------------------------------------------------------------
  2.7  Q&A query helpers

  These are the only Layer 2 predicates that name a specific parameter by
  atom — because they ARE the answer to "what depends on parameter X?"
  That question is inherently parameter-specific.

  components_requiring_param(+Param, +Value, -Names)
  variants_for_param_value(+Product, +Param, +Value, -Configs)
-----------------------------------------------------------------------------*/

components_requiring_param(Param, Value, Names) :-
    product(Product),
    product_structure(Product, Structure),
    findall(Name,
        (   member(Comp, Structure),
            Comp.requires = param(Param, TriggerVals),
            member(Value, TriggerVals),
            Name = Comp.name
        ),
        Names).

variants_for_param_value(Product, Param, Value, Configs) :-
    findall(C,
        (product_variant(Product, C), config_get(C, Param, Value)),
        Configs).


/*=============================================================================
  LAYER 3 — QUERY / CLI HELPERS
  Calls ONLY Layer 2 interfaces (and product_parameters/2 / parameter_values/2
  for the two catalogue-inspection helpers, which are display-only).
  No component/3, no product_structure/2, no service_item/3 directly.
=============================================================================*/

/*-----------------------------------------------------------------------------
  3.0  Parameters and variants — catalogue inspection
-----------------------------------------------------------------------------*/

% list_parameters/1 — catalogue inspection (Layer 1 exception: read-only display)
% CLI: list_parameters(diesel_generator).
list_parameters(Product) :-
    product_parameters(Product, Params),
    format("Parameters of ~w:~n", [Product]),
    forall(member(P, Params), format("  ~w~n", [P])).

% list_values/1 — catalogue inspection
% CLI: list_values(emission).
list_values(Param) :-
    parameter_values(Param, Values),
    format("Values for ~w:~n", [Param]),
    forall(member(V, Values), format("  ~w~n", [V])).

% list_variants/1
% CLI: list_variants(diesel_generator).
list_variants(Product) :-
    product_variant(Product, Config),
    format("  ~w~n", [Config]),
    fail.
list_variants(_).

% count_variants/2
% CLI: count_variants(diesel_generator, N).
count_variants(Product, N) :-
    findall(C, product_variant(Product, C), Cs),
    length(Cs, N).

% list_variants_with_count/1
% CLI: list_variants_with_count(diesel_generator).
list_variants_with_count(Product) :-
    findall(C, product_variant(Product, C), Configs),
    length(Configs, Total),
    forall(member(C, Configs), format("  ~w~n", [C])),
    format("~nTotal variants: ~w~n", [Total]).

% list_configs_by_price/1
% CLI: list_configs_by_price(diesel_generator).
list_configs_by_price(Product) :-
    all_configs_by_price(Product, Sorted),
    forall(
        member(Price-Config, Sorted),
        format("  ~w DKK  →  ~w~n", [Price, Config])
    ).

% print_config_summary/2
% CLI: product_variant(diesel_generator, Config),
%      config_get(Config, apparent_power, kva_400), !,
%      print_config_summary(diesel_generator, Config).
print_config_summary(Product, Config) :-
    config_price(Product, Config, Price),
    config_bom(Product, Config, BoMNodes),
    format("~n--- Configuration Summary ---~n", []),
    format("  Config : ~w~n", [Config]),
    format("  Price  : ~w DKK~n", [Price]),
    format("  BoM entries:~n", []),
    forall(
        member(bom_node(Name, Article, Qty, _), BoMNodes),
        format("    ~w  x~w  ~w~n", [Name, Qty, Article])
    ).

/*-----------------------------------------------------------------------------
  3.1  BoM inspection
-----------------------------------------------------------------------------*/

%-------------------------------------------------------------
% list_component_types/0
% List all unique component types defined in the ontology.
% CLI: list_component_types.
%-------------------------------------------------------------
list_component_types :-
    findall(Type,
        (   product(Product),
            component(Product, _, D),
            Type = D.type
        ),
        Types),
    sort(Types, Unique),
    format("~nComponent types:~n", []),
    forall(member(T, Unique), format("  ~w~n", [T])).

%-------------------------------------------------------------
% list_components_of_type/1
% List all components of a given type across all products.
% CLI: list_components_of_type(static_equipment).
%      list_components_of_type(minor).
%-------------------------------------------------------------
list_components_of_type(Type) :-
    format("~nComponents of type '~w':~n", [Type]),
    findall(Name-Article,
        (   product(Product),
            component(Product, Name, D),
            D.type = Type,
            Article = D.article
        ),
        Pairs),
    sort(Pairs, Unique),
    (   Unique = []
    ->  format("  (none found)~n", [])
    ;   forall(member(Name-Article, Unique),
               format("  ~w  (~w)~n", [Name, Article]))
    ).

%-------------------------------------------------------------
% list_vendors/0
% List all unique vendors defined in the ontology.
% CLI: list_vendors.
%-------------------------------------------------------------
list_vendors :-
    findall(Vendor,
        (   product(Product),
            component(Product, _, D),
            Vendor = D.vendor
        ),
        Vendors),
    sort(Vendors, Unique),
    format("~nVendors:~n", []),
    forall(member(V, Unique), format("  ~w~n", [V])).

%-------------------------------------------------------------
% list_components_by_vendor/1
% List all components supplied by a given vendor.
% CLI: list_components_by_vendor('Dinex').
%      list_components_by_vendor('ABZ').
%-------------------------------------------------------------
list_components_by_vendor(Vendor) :-
    format("~nComponents from vendor '~w':~n", [Vendor]),
    findall(Name-Article,
        (   product(Product),
            component(Product, Name, D),
            D.vendor = Vendor,
            Article = D.article
        ),
        Pairs),
    sort(Pairs, Unique),
    (   Unique = []
    ->  format("  (none found)~n", [])
    ;   forall(member(Name-Article, Unique),
               format("  ~w  (~w)~n", [Name, Article]))
    ).

%-------------------------------------------------------------
% list_components_by_replaceability/1
% List all components by their replaceable flag.
% CLI: list_components_by_replaceability(true).
%      list_components_by_replaceability(false).
%-------------------------------------------------------------
list_components_by_replaceability(Flag) :-
    (   Flag = true
    ->  Label = "replaceable"
    ;   Label = "non-replaceable"
    ),
    format("~nComponents marked as ~w:~n", [Label]),
    findall(Name-Article,
        (   product(Product),
            component(Product, Name, D),
            D.replaceable = Flag,
            Article = D.article
        ),
        Pairs),
    sort(Pairs, Unique),
    (   Unique = []
    ->  format("  (none found)~n", [])
    ;   forall(member(Name-Article, Unique),
               format("  ~w  (~w)~n", [Name, Article]))
    ).

%-------------------------------------------------------------
% list_components_by_service_interval/2
% List components whose service interval is below or above
% a given threshold in hours.
% Mode is: below | above
% CLI: list_components_by_service_interval(below, 5000).
%      list_components_by_service_interval(above, 9000).
%-------------------------------------------------------------
list_components_by_service_interval(Mode, Threshold) :-
    (   Mode = below
    ->  format("~nComponents with service interval below ~w h:~n",
               [Threshold])
    ;   format("~nComponents with service interval above ~w h:~n",
               [Threshold])
    ),
    findall(Name-Article-Interval,
        (   product(Product),
            component(Product, Name, D),
            Interval = D.service_interval_hours,
            (   Mode = below
            ->  Interval < Threshold
            ;   Interval > Threshold
            ),
            Article = D.article
        ),
        Triples),
    sort(Triples, Unique),
    (   Unique = []
    ->  format("  (none found)~n", [])
    ;   forall(
            member(Name-Article-Interval, Unique),
            format("  ~w  (~w)  ~w h~n", [Name, Article, Interval])
        )
    ).

/*-----------------------------------------------------------------------------
  3.2  Servicce inspection
-----------------------------------------------------------------------------*/

% list_service_items/0
% CLI: list_service_items.
list_service_items :-
    format("~nAvailable service items:~n", []),
    findall(Item, service_parameter_values(Item, variant, _), Items),
    forall(
        member(Item, Items),
        (   service_parameter_values(Item, variant, Variants),
            format("  ~w~n", [Item]),
            forall(
                member(VK, Variants),
                (   service_item(Item, VK, D),
                    format("    ~w  →  ~w DKK  (~w)~n",
                           [VK, D.price_dkk, D.description])
                )
            )
        )
    ).

% list_available_service_items/1
% CLI: list_available_service_items(eu_stage_5).
list_available_service_items(Emission) :-
    format("~nService items available for ~w:~n", [Emission]),
    findall(Item, service_parameter_values(Item, variant, _), Items),
    forall(
        member(Item, Items),
        (   findall(VK-P,
                (   service_parameter_values(Item, variant, Vs),
                    member(VK, Vs),
                    service_item_available(Item, VK, Emission),
                    service_item(Item, VK, D), P = D.price_dkk ),
                Avail),
            ( Avail \= []
            -> format("  ~w~n", [Item]),
               forall(member(VK-P, Avail),
                      format("    ~w  →  ~w DKK~n", [VK, P]))
            ;  true )
        )
    ).

% print_service_scope_summary/2
% CLI: print_service_scope_summary(
%          [genset_service-standard, warranty-warranty_5yr], eu_stage_5).
print_service_scope_summary(Scope, Emission) :-
    service_scope_price(Scope, Emission, Total),
    format("~n--- Service Scope Summary  (emission: ~w) ---~n", [Emission]),
    forall(
        member(Item-VK, Scope),
        ( service_variant(Item, VK, Emission, D)
        -> format("  ~w/~w  →  ~w DKK  (~w)~n",
                  [Item, VK, D.price_dkk, D.description])
        ;  format("  ~w/~w  →  N/A for ~w~n", [Item, VK, Emission])
        )
    ),
    format("  Total: ~w DKK~n", [Total]).


/*=============================================================================
  LAYER 4 — PRESENTATION
  Calls ONLY Layer 2 interfaces (config_bom/3, config_price/3,
  service_variant/4, service_scope_price/3) and Layer 3 helpers.
  Knows nothing about parameter names, component names, or ontology structure.
  Receives opaque Config and opaque bom_node/4 terms.
=============================================================================*/

/*-----------------------------------------------------------------------------
  4.1  BoM tree printer

  print_bom_tree(+Product, +Config)

  Config can be obtained by:
    a) Querying:  product_variant(Product, Config), config_get(Config,...), !
    b) Directly:  [apparent_power-kva_400, voltage-v_400, frequency-hz_50,
                   emission-eu_stage_5, certification-ce]

  CLI (option a):
    product_variant(diesel_generator, Config),
    config_get(Config, apparent_power, kva_400),
    config_get(Config, emission, eu_stage_5), !,
    print_bom_tree(diesel_generator, Config).

  CLI (option b):
    print_bom_tree(diesel_generator,
        [apparent_power-kva_400, voltage-v_400, frequency-hz_50,
         emission-eu_stage_5, certification-ce]).
-----------------------------------------------------------------------------*/

print_bom_tree(Product, Config) :-
    config_price(Product, Config, Price),
    config_bom(Product, Config, BoMNodes),
    format("~n~`=t~60|~n", []),
    format("DIESEL GENERATOR — Bill of Materials~n", []),
    format("  Config : ~w~n", [Config]),
    format("  Price  : ~w DKK~n", [Price]),
    format("~`=t~60|~n~n", []),
    format("diesel_generator~n", []),
    print_bom_items(BoMNodes, "").

print_bom_items([], _).
print_bom_items([Node], Prefix) :-
    !, print_bom_node(Node, Prefix, "└─ ", "   ").
print_bom_items([Node|Rest], Prefix) :-
    print_bom_node(Node, Prefix, "├─ ", "│  "),
    print_bom_items(Rest, Prefix).

print_bom_node(bom_node(Name, Article, Qty, Subs),
               Prefix, Branch, ChildPfx) :-
    ( Qty > 1
    -> format("~w~w~w  x~w  (~w)~n", [Prefix, Branch, Name, Qty, Article])
    ;  format("~w~w~w  (~w)~n",       [Prefix, Branch, Name, Article])
    ),
    ( Subs \= []
    -> atom_concat(Prefix, ChildPfx, NewPfx),
       print_leaf_items(Subs, NewPfx)
    ;  true
    ).

print_leaf_items([], _).
print_leaf_items([S], Pfx) :- !, format("~w└─ ~w~n", [Pfx, S]).
print_leaf_items([S|Rest], Pfx) :-
    format("~w├─ ~w~n", [Pfx, S]),
    print_leaf_items(Rest, Pfx).

/*-----------------------------------------------------------------------------
  4.2  Service tree printer

  print_service_tree(+Scope, +Emission)
    Scope = [ItemName-VariantKey, ...]

  CLI:
    print_service_tree(
        [genset_service-standard, cabinet_service-extended,
         commissioning-full, scr_service-extended,
         warranty-warranty_5yr, remote_monitoring-advanced],
        eu_stage_5).

  print_cheapest_service_scope(+Emission)
    Convenience: builds cheapest-per-item scope, then calls print_service_tree.
-----------------------------------------------------------------------------*/

print_service_tree(Scope, Emission) :-
    include(svc_available_for(Emission), Scope, ValidScope),
    service_scope_price(ValidScope, Emission, Total),
    format("~n~`=t~60|~n", []),
    format("SERVICE SCOPE — Bill of Services~n", []),
    format("  Emission context : ~w~n", [Emission]),
    format("  Total price      : ~w DKK~n", [Total]),
    format("~`=t~60|~n~n", []),
    format("service_scope~n", []),
    print_svc_items(ValidScope, Emission, "").

svc_available_for(Emission, Item-VK) :-
    service_item_available(Item, VK, Emission).

print_svc_items([], _, _).
print_svc_items([Node], Emission, Pfx) :-
    !, print_svc_node(Node, Emission, Pfx, "└─ ", "   ").
print_svc_items([Node|Rest], Emission, Pfx) :-
    print_svc_node(Node, Emission, Pfx, "├─ ", "│  "),
    print_svc_items(Rest, Emission, Pfx).

print_svc_node(Item-VK, Emission, Pfx, Branch, ChildPfx) :-
    service_variant(Item, VK, Emission, D),
    ( D.interval =:= 0 -> IStr = "one-time"
    ; format(atom(IStr), "~w h", [D.interval]) ),
    format("~w~w~w  [~w DKK]  (~w)~n",
           [Pfx, Branch, Item, D.price_dkk, VK]),
    atom_concat(Pfx, ChildPfx, NewPfx),
    format("~w    ~w  |  ~w~n", [NewPfx, D.description, IStr]),
    ( get_dict(sub_items, D, Subs), Subs \= []
    -> print_leaf_items(Subs, NewPfx)
    ;  true ).

print_cheapest_service_scope(Emission) :-
    findall(Item, service_parameter_values(Item, variant, _), Items),
    findall(Item-VK,
        (member(Item, Items), service_cheapest_variant(Item, Emission, VK, _)),
        Scope),
    sort(Scope, UniqScope),
    print_service_tree(UniqScope, Emission).


/*=============================================================================
  LAYER 5 — VALIDATION
  Checks ontology integrity after any Layer 1 modification.
  Calls Layer 2 helpers (product_variant, used_in_matches) and
  Layer 1 facts directly (because validation IS about Layer 1 structure).
=============================================================================*/

validate_ontology :-
    format("~n~`=t~60|~n", []),
    format("ONTOLOGY VALIDATION~n", []),
    format("~`=t~60|~n~n", []),
    validate_v1, validate_v2, validate_v3, validate_v4,
    validate_v5, validate_v6, validate_v7, validate_v8, validate_v9,
    format("~n~`=t~60|~n", []),
    format("Validation complete.~n", []),
    format("~`=t~60|~n~n", []).

validate_v1 :-
    format("[V1] Every declared parameter has a domain...~n", []),
    product_parameters(diesel_generator, Params),
    forall(member(P, Params),
        ( parameter_values(P, _)
        ->  format("    OK   ~w~n", [P])
        ;   format("    ERR  ~w — no parameter_values/2!~n", [P]) )).

validate_v2 :-
    format("[V2] product_structure component refs exist...~n", []),
    product_structure(diesel_generator, S),
    forall(member(C, S),
        ( component(diesel_generator, C.name, _)
        ->  format("    OK   ~w~n", [C.name])
        ;   format("    ERR  ~w — no component/3!~n", [C.name]) )).

validate_v3 :-
    format("[V3] used_in specs are valid...~n", []),
    forall(
        component(diesel_generator, Name, D),
        forall(member(Spec, D.used_in),
            ( valid_used_in(Spec)
            ->  format("    OK   ~w  ~w~n", [Name, Spec])
            ;   format("    ERR  ~w  bad used_in: ~w~n", [Name, Spec]) ))).

valid_used_in(any).
valid_used_in(v(P,F)) :-
    parameter_values(apparent_power, Ps), member(P, Ps),
    parameter_values(frequency,      Fs), member(F, Fs).
valid_used_in(E) :-
    parameter_values(emission, Es), member(E, Es).

validate_v4 :-
    format("[V4] Sub-component references...~n", []),
    forall(
        ( component(diesel_generator, Name, D),
          get_dict(sub_components, D, Subs), member(Sub, Subs) ),
        ( component(diesel_generator, Sub, _)
        ->  format("    OK   ~w → ~w~n", [Name, Sub])
        ;   format("    NOTE ~w → ~w  (leaf atom, no component/3 needed)~n",
                   [Name, Sub]) )).

validate_v5 :-
    format("[V5] Every component variant is reachable...~n", []),
    forall(
        component(diesel_generator, Name, D),
        ( findall(C,
              (product_variant(diesel_generator, C),
               member(Spec, D.used_in),
               used_in_matches(Spec, C)),
              Matches),
          ( Matches \= []
          ->  length(Matches, N),
              format("    OK   ~w  (~w variants)~n", [D.article, N])
          ;   format("    ERR  ~w (~w) — unreachable!~n", [D.article, Name]) )
        )).

validate_v6 :-
    format("[V6] Compatibility rule values are declared...~n", []),
    parameter_values(voltage,       Vs),
    parameter_values(frequency,     Fs),
    parameter_values(emission,      Es),
    parameter_values(certification, Cs),
    forall(compatible_voltage_frequency(V, F),
        ( (member(V, Vs), member(F, Fs))
        ->  format("    OK   vf(~w,~w)~n", [V,F])
        ;   format("    ERR  vf(~w,~w) unknown!~n", [V,F]) )),
    forall(compatible_emission_certification(E, C),
        ( (member(E, Es), member(C, Cs))
        ->  format("    OK   ec(~w,~w)~n", [E,C])
        ;   format("    ERR  ec(~w,~w) unknown!~n", [E,C]) )).

validate_v7 :-
    format("[V7] Every service item has variant facts...~n", []),
    findall(Item, service_parameter_values(Item, variant, _), Items),
    forall(member(Item, Items),
        ( service_parameter_values(Item, variant, Variants),
          forall(member(VK, Variants),
              ( service_item(Item, VK, _)
              ->  format("    OK   ~w/~w~n", [Item, VK])
              ;   format("    ERR  ~w/~w — no service_item/3!~n", [Item, VK]) ))
        )).

validate_v8 :-
    format("[V8] Service applies_to values are valid...~n", []),
    service_parameter_values(emission, ValidE),
    forall(service_item(Item, VK, D),
        forall(member(E, D.applies_to),
            ( (E = any ; member(E, ValidE))
            ->  format("    OK   ~w/~w  ~w~n", [Item, VK, E])
            ;   format("    ERR  ~w/~w  ~w unknown!~n", [Item, VK, E]) ))).

validate_v9 :-
    format("[V9] Service variant keys are registered...~n", []),
    forall(service_item(Item, VK, _),
        ( service_parameter_values(Item, variant, Vs), member(VK, Vs)
        ->  format("    OK   ~w/~w~n", [Item, VK])
        ;   format("    ERR  ~w/~w — not in service_parameter_values!~n",
                   [Item, VK]) )).


/*=============================================================================
  MENU SYSTEM
  Structured navigation across five sections + an info screen.

  Public interface:
    menu.      — main menu (overview of all sections)
    menu(0).   — Info & Help  (Prolog basics, version, copyright)
    menu(1).   — Ontology     (Layer 1 inspection predicates)
    menu(2).   — Reasoner     (Layer 2 logic predicates)
    menu(3).   — Queries      (Layer 3 CLI helpers)
    menu(4).   — Presentation (Layer 4 tree printers)
    menu(5).   — Validation   (Layer 5 integrity checks)

  Design:
    - No state, no routing table, no call/1 dispatch.
    - Each menu/1 clause is a standalone display predicate.
    - The REPL IS the shell — predicate names are the commands.
    - Navigation footer is identical on every screen.
=============================================================================*/

% nav_footer/0 — printed at the bottom of every screen
nav_footer :-
    format("~n~`-t~60|~n", []),
    format("  Navigation:~n", []),
    format("    menu.      back to main menu~n", []),
    format("    menu(N).   open section N  (0=Info, 1-6=sections)~n", []),
    format("    halt.      exit SWI-Prolog~n", []),
    format("~`=t~60|~n~n", []).

%-----------------------------------------------------------------------------
% menu/0 — main menu
%-----------------------------------------------------------------------------
menu :-
    format("~n~`=t~60|~n", []),
    format("  DIESEL GENERATOR CONFIGURATOR  v2.0~n", []),
    format("  SWI-Prolog Expert Configurator~n", []),
    format("~`=t~60|~n~n", []),
    format("  menu(0).   Info & Help~n",   []),
    format("  menu(1).   Ontology       — inspect parameters & components~n", []),
    format("  menu(2).   Reasoner       — variants, BoM, pricing logic~n",    []),
    format("  menu(3).   Queries        — list, count, summarise~n",           []),
    format("  menu(4).   Presentation   — tree printers~n",                    []),
    format("  menu(5).   Validation     — ontology integrity checks~n",        []),
    format("  menu(6).   Graphics       — ASCII diagrams~n",                   []),
    nav_footer.

%-----------------------------------------------------------------------------
% menu(0) — Info & Help
%-----------------------------------------------------------------------------
menu(0) :-
    format("~n~`=t~60|~n", []),
    format("  INFO & HELP~n", []),
    format("~`=t~60|~n~n", []),

    format("  Program  : Diesel Generator Expert Configurator~n", []),
    format("  Version  : 2.0~n", []),
    format("  Platform : SWI-Prolog 9.x  (threaded, 64-bit)~n", []),
    format("  Author   : —~n", []),
    format("  License  : proprietary / internal use~n", []),

    format("~n  ABOUT~n", []),
    format("  This system generates valid product configurations for~n", []),
    format("  diesel generators, resolves Bills of Materials, calculates~n",[]),
    format("  pricing, and configures service scopes. The knowledge base~n",[]),
    format("  (ontology) is fully separated from reasoning logic so that~n",[]),
    format("  new products, parameters, and components can be added by~n", []),
    format("  editing only the ontology section of the source file.~n", []),

    format("~n  BASIC PROLOG COMMANDS~n", []),
    format("    halt.                   exit SWI-Prolog~n", []),
    format("    Ctrl+C  then  a.        abort current query~n", []),
    format("    Ctrl+C  then  c.        continue after interrupt~n", []),
    format("    trace.                  enable step-by-step debugger~n", []),
    format("    notrace.                disable debugger~n", []),
    format("    listing(predicate/N).   show source of predicate~n", []),
    format("    apropos(keyword).       search predicates by keyword~n", []),
    format("    help(predicate).        show built-in help~n", []),

    format("~n  QUERY TIPS~n", []),
    format("    ;   after a result asks for the next solution~n", []),
    format("    .   after a result accepts and stops~n", []),
    format("    Variables start with a capital letter: Config, X, N~n", []),
    format("    Every query ends with a full stop: predicate(args).~n", []),
    format("    !   in the end of a query prevents backtracking~n", []),

    format("~n  TYPICAL WORKFLOW~n", []),
    format("    1. Generate a Config:~n", []),
    format("       product_variant(diesel_generator, Config),~n", []),
    format("       config_get(Config, apparent_power, kva_400),~n", []),
    format("       config_get(Config, emission, eu_stage_5), !.~n", []),
    format("    2. Inspect it:~n", []),
    format("       print_bom_tree(diesel_generator, Config).~n", []),
    format("    3. Price it:~n", []),
    format("       config_price(diesel_generator, Config, Price).~n", []),
    format("    4. Add a service scope:~n", []),
    format("       print_service_tree(~n", []),
    format("           [genset_service-standard, warranty-warranty_5yr],~n",[]),
    format("           eu_stage_5).~n", []),
    nav_footer.

%-----------------------------------------------------------------------------
% menu(1) — Ontology
%-----------------------------------------------------------------------------
menu(1) :-
    format("~n~`=t~60|~n", []),
    format("  1. ONTOLOGY — inspect parameters & components~n", []),
    format("~`=t~60|~n~n", []),

    format("  Inspect product parameters~n", []),
    format("    list_parameters(diesel_generator).~n", []),
    format("~n  Inspect values for one parameter~n", []),
    format("    list_values(apparent_power).~n", []),
    format("    list_values(voltage).~n", []),
    format("    list_values(frequency).~n", []),
    format("    list_values(emission).~n", []),
    format("    list_values(certification).~n", []),
    format("~n  Inspect service catalogue~n", []),
    format("    list_service_items.~n", []),
    format("    list_available_service_items(eu_stage_5).~n", []),
    format("    list_available_service_items(eu_stage_3).~n", []),
    format("    list_available_service_items(epa_tier_4).~n", []),
    nav_footer.

%-----------------------------------------------------------------------------
% menu(2) — Reasoner
%-----------------------------------------------------------------------------
menu(2) :-
    format("~n~`=t~60|~n", []),
    format("  2. REASONER — variants, BoM, pricing logic~n", []),
    format("~`=t~60|~n~n", []),

    format("  Generate all valid configurations (backtrack with ;)~n", []),
    format("    product_variant(diesel_generator, Config).~n", []),
    format("~n  Read one value from a Config~n", []),
    format("    config_get(Config, apparent_power, V).~n", []),
    format("    config_get(Config, emission, V).~n", []),
    format("~n  Resolve Bill of Materials for a Config~n", []),
    format("    config_bom(diesel_generator, Config, BoM).~n", []),
    format("~n  Calculate total price for a Config~n", []),
    format("    config_price(diesel_generator, Config, Price).~n", []),
    format("~n  Price extremes~n", []),
    format("    cheapest_configs(diesel_generator, Configs, Price).~n", []),
    format("    most_expensive_configs(diesel_generator, Configs, Price).~n",[]),
    format("    all_configs_by_price(diesel_generator, Sorted).~n", []),
    format("~n  Service reasoning~n", []),
    format("    service_variant(genset_service, standard, eu_stage_5, D).~n",[]),
    format("    service_item_available(scr_service, standard, eu_stage_5).~n",[]),
    format("    all_available_service_variants(eu_stage_5, Pairs).~n", []),
    format("    service_cheapest_variant(genset_service, eu_stage_5, VK, Price).~n",[]),
    format("    service_most_expensive_variant(genset_service, eu_stage_5, VK, Price).~n",[]),
    format("    service_scope_price(~n", []),
    format("        [genset_service-standard, warranty-warranty_5yr],~n", []),
    format("        eu_stage_5, Total).~n", []),
    format("~n  Q&A helpers~n", []),
    format("    components_requiring_param(emission, eu_stage_5, Names).~n",[]),
    format("    variants_for_param_value(diesel_generator,~n", []),
    format("        apparent_power, kva_400, Configs).~n", []),
    nav_footer.

%-----------------------------------------------------------------------------
% menu(3) — Queries
%-----------------------------------------------------------------------------
menu(3) :-
    format("~n~`=t~60|~n", []),
    format("  3. QUERIES — list, count, summarise~n", []),
    format("~`=t~60|~n~n", []),

    format("  List / count configurations~n", []),
    format("    list_variants(diesel_generator).~n", []),
    format("    list_variants_with_count(diesel_generator).~n", []),
    format("    count_variants(diesel_generator, N).~n", []),
    format("~n  Configurations sorted by price~n", []),
    format("    list_configs_by_price(diesel_generator).~n", []),
    format("~n  Full configuration summary (BoM + price flat list)~n", []),
    format("    %% First obtain a Config (see menu(2)), then:~n", []),
    format("    print_config_summary(diesel_generator, Config).~n", []),
    format("~n  Component inspection~n", []),
    format("    list_component_types.~n", []),
    format("    list_components_of_type(static_equipment).~n", []),
    format("    list_vendors.~n", []),
    format("    list_components_by_vendor('Dinex').~n", []),
    format("    list_components_by_replaceability(true).~n", []),
    format("    list_components_by_replaceability(false).~n", []),
    format("    list_components_by_service_interval(below, 5000).~n", []),
    format("    list_components_by_service_interval(above, 9000).~n", []),
    format("~n  Service scope summary (flat list + total)~n", []),
    format("    print_service_scope_summary(~n", []),
    format("        [genset_service-standard,~n", []),
    format("         cabinet_service-extended,~n", []),
    format("         warranty-warranty_5yr],~n", []),
    format("        eu_stage_5).~n", []),
    nav_footer.

%-----------------------------------------------------------------------------
% menu(4) — Presentation
%-----------------------------------------------------------------------------
menu(4) :-
    format("~n~`=t~60|~n", []),
    format("  4. PRESENTATION — tree printers~n", []),
    format("~`=t~60|~n~n", []),

    format("  BoM tree — query Config then print~n", []),
    format("    product_variant(diesel_generator, Config),~n", []),
    format("    config_get(Config, apparent_power, kva_400),~n", []),
    format("    config_get(Config, emission, eu_stage_5), !,~n", []),
    format("    print_bom_tree(diesel_generator, Config).~n", []),
    format("~n  BoM tree — supply Config directly~n", []),
    format("    print_bom_tree(diesel_generator,~n", []),
    format("        [apparent_power-kva_400, voltage-v_400,~n", []),
    format("         frequency-hz_50, emission-eu_stage_5,~n", []),
    format("         certification-ce]).~n", []),
    format("~n  Service tree — chosen scope~n", []),
    format("    print_service_tree(~n", []),
    format("        [genset_service-standard,~n", []),
    format("         cabinet_service-extended,~n", []),
    format("         commissioning-full,~n", []),
    format("         scr_service-extended,~n", []),
    format("         warranty-warranty_5yr,~n", []),
    format("         remote_monitoring-advanced],~n", []),
    format("        eu_stage_5).~n", []),
    format("~n  Service tree — cheapest available per item~n", []),
    format("    print_cheapest_service_scope(eu_stage_5).~n", []),
    format("    print_cheapest_service_scope(eu_stage_3).~n", []),
    format("    print_cheapest_service_scope(epa_tier_4).~n", []),
    nav_footer.

%-----------------------------------------------------------------------------
% menu(5) — Validation
%-----------------------------------------------------------------------------
menu(5) :-
    format("~n~`=t~60|~n", []),
    format("  5. VALIDATION — ontology integrity checks~n", []),
    format("~`=t~60|~n~n", []),

    format("  Run all checks (V1-V9)~n", []),
    format("    validate_ontology.~n", []),
    format("~n  What the checks cover:~n", []),
    format("    V1  every declared parameter has a domain~n", []),
    format("    V2  every product_structure entry has a component/3 fact~n",[]),
    format("    V3  all used_in specs reference valid parameter values~n",  []),
    format("    V4  sub-component atoms noted as leaf or registered~n",     []),
    format("    V5  every component variant reachable by >=1 config~n",     []),
    format("    V6  compatibility rule atoms are declared values~n",         []),
    format("    V7  every service item has variant facts~n",                 []),
    format("    V8  service applies_to values are valid emission atoms~n",   []),
    format("    V9  service variant keys match parameter declarations~n",    []),
    format("~n  When to run:~n", []),
    format("    After any edit to the ONTOLOGY section of the source.~n", []),
    format("    A clean run prints only OK lines and 'Validation complete.'~n",[]),
    nav_footer.

%-----------------------------------------------------------------------------
% menu(6) — Graphics
%-----------------------------------------------------------------------------
menu(6) :-
    format("~n~`=t~60|~n", []),
    format("  6. GRAPHICS — ASCII diagrams~n", []),
    format("~`=t~60|~n~n", []),
    format("  Single-line diagram display~n", []),
    format("    diagram(single_line).~n", []),
    format("~n  All available diagrams~n", []),
    format("    list_diagrams.~n", []),
    nav_footer.

%-----------------------------------------------------------------------------
% Catch-all for unknown section numbers
%-----------------------------------------------------------------------------
menu(N) :-
    integer(N),
    \+ member(N, [0,1,2,3,4,5,6]),
    format("~n  Unknown section: ~w~n", [N]),
    format("  Valid sections: 0 (Info) through 6 (Graphics).~n~n", []),
    menu.
 
% main/0 — entry point for the standalone executable.
% Prints the main menu then hands control to the interactive REPL.
% Used by: swipl ... qsave_program(..., goal(main), ...)
main :- menu, prolog.
 
:- initialization(menu).