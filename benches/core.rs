use criterion::{black_box, criterion_group, criterion_main, Criterion};
use systower::{
    config::Config,
    policy::{ContainerFacts, ContainerPolicy},
};

fn policy_decision(c: &mut Criterion) {
    let policy = ContainerPolicy {
        include_only: vec!["api".into()],
        exclude: Vec::new(),
        protect_network: true,
        protect_socket: true,
    };
    let facts = ContainerFacts {
        name: "api".into(),
        ..Default::default()
    };
    c.bench_function("policy_decision", |bench| {
        bench.iter(|| black_box(policy.allows(black_box(&facts))))
    });
}

fn config_defaults(c: &mut Criterion) {
    c.bench_function("config_defaults", |bench| {
        bench.iter(|| black_box(Config::from_env().unwrap()))
    });
}

criterion_group!(benches, policy_decision, config_defaults);
criterion_main!(benches);
