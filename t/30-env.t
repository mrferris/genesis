#!/usr/bin/perl
use strict;
use warnings;
use utf8;

use lib 'lib';
use lib 't';
use helper;
use Test::Exception;
use Test::Deep;
use Test::Output;
use Test::Differences;

use_ok 'Genesis::Env';
use Genesis::BOSH;
use Genesis::Top;
use Genesis;

fake_bosh;

subtest 'new() validation' => sub {
	throws_ok { Genesis::Env->new() }
		qr/no 'name' specified.*this is a bug/is;

	throws_ok { Genesis::Env->new(name => 'foo') }
		qr/no 'top' specified.*this is a bug/is;
};

subtest 'name validation' => sub {
	lives_ok { Genesis::Env->_validate_env_name("my-new-env"); }
		"my-new-env is a good enough name";

	throws_ok { Genesis::Env->_validate_env_name(""); }
		qr/must not be empty/i;

	throws_ok { Genesis::Env->_validate_env_name("my\tnew env\n"); }
		qr/must not contain whitespace/i;

	throws_ok { Genesis::Env->_validate_env_name("my-new-!@#%ing-env"); }
		qr/can only contain lowercase letters, numbers, and hyphens/i;

	throws_ok { Genesis::Env->_validate_env_name("-my-new-env"); }
		qr/must start with a .*letter/i;
	throws_ok { Genesis::Env->_validate_env_name("my-new-env-"); }
		qr/must not end with a hyphen/i;

	throws_ok { Genesis::Env->_validate_env_name("my--new--env"); }
		qr/must not contain sequential hyphens/i;

	for my $ok (qw(
		env1
		us-east-1-prod
		this-is-a-really-long-hyphenated-name-oh-god-why-would-you-do-this-to-yourself
		company-us_east_1-prod
	)) {
		lives_ok { Genesis::Env->_validate_env_name($ok); } "$ok is a valid env name";
	}
};

subtest 'loading' => sub {
	my $vault_target = vault_ok;
	Genesis::Vault->clear_all();
	my $top = Genesis::Top->create(workdir, 'thing', vault=>$VAULT_URL);
	$top->link_dev_kit('t/src/simple');
	put_file $top->path("standalone.yml"), <<EOF;
---
kit:
  name:    dev
  version: latest
  features: []

genesis: {}
EOF

	lives_ok { $top->load_env('standalone') }
	         "should be able to load the `standalone' environment.";
	lives_ok { $top->load_env('standalone.yml') }
	         "should be able to load an environment by filename.";
	teardown_vault();
};

subtest 'env-to-env relation' => sub {
	my $a = bless({ name => "us-west-1-preprod-a" }, 'Genesis::Env');
	my $b = bless({ name => "us-west-1-prod"      }, 'Genesis::Env');

	cmp_deeply([$a->relate($b)], [qw[
			./us.yml
			./us-west.yml
			./us-west-1.yml
			./us-west-1-preprod.yml
			./us-west-1-preprod-a.yml
		]], "(us-west-1-preprod-a)->relate(us-west-1-prod) should return correctly");

	cmp_deeply([$a->relate($b, ".cache")], [qw[
			.cache/us.yml
			.cache/us-west.yml
			.cache/us-west-1.yml
			./us-west-1-preprod.yml
			./us-west-1-preprod-a.yml
		]], "relate() should handle cache prefixes, if given");

	cmp_deeply([$a->relate($b, ".cache", "TOP/LEVEL")], [qw[
			.cache/us.yml
			.cache/us-west.yml
			.cache/us-west-1.yml
			TOP/LEVEL/us-west-1-preprod.yml
			TOP/LEVEL/us-west-1-preprod-a.yml
		]], "relate() should handle cache and top prefixes, if both are given");

	cmp_deeply([$a->relate("us-east-sandbox", ".cache", "TOP/LEVEL")], [qw[
			.cache/us.yml
			TOP/LEVEL/us-west.yml
			TOP/LEVEL/us-west-1.yml
			TOP/LEVEL/us-west-1-preprod.yml
			TOP/LEVEL/us-west-1-preprod-a.yml
		]], "relate() should take names for \$them, in place of actual Env objects");

	cmp_deeply([$a->relate($a, ".cache", "TOP/LEVEL")], [qw[
			.cache/us.yml
			.cache/us-west.yml
			.cache/us-west-1.yml
			.cache/us-west-1-preprod.yml
			.cache/us-west-1-preprod-a.yml
		]], "relate()-ing an env to itself should work (if a little depraved)");

	cmp_deeply([$a->relate(undef, ".cache", "TOP/LEVEL")], [qw[
			TOP/LEVEL/us.yml
			TOP/LEVEL/us-west.yml
			TOP/LEVEL/us-west-1.yml
			TOP/LEVEL/us-west-1-preprod.yml
			TOP/LEVEL/us-west-1-preprod-a.yml
		]], "relate()-ing to nothing (undef) should treat everything as unique");

	cmp_deeply(scalar $a->relate($b, ".cache", "TOP/LEVEL"), {
			common => [qw[
				.cache/us.yml
				.cache/us-west.yml
				.cache/us-west-1.yml
			]],
			unique => [qw[
				TOP/LEVEL/us-west-1-preprod.yml
				TOP/LEVEL/us-west-1-preprod-a.yml
			]],
		}, "relate() in scalar mode passes back a hashref");

	{
		local $ENV{PREVIOUS_ENV} = 'us-west-1-sandbox';
		cmp_deeply([$a->potential_environment_files()], [qw[
				.genesis/cached/us-west-1-sandbox/us.yml
				.genesis/cached/us-west-1-sandbox/us-west.yml
				.genesis/cached/us-west-1-sandbox/us-west-1.yml
				./us-west-1-preprod.yml
				./us-west-1-preprod-a.yml
			]], "potential_environment_files() called with PREVIOUS_ENV should leverage the Genesis cache");
		}
};

subtest 'environment metadata' => sub {
	my $vault_target = vault_ok;
	Genesis::Vault->clear_all();
	my $top = Genesis::Top->create(workdir, 'thing', vault=>$VAULT_URL);
	$top->download_kit('bosh/0.2.0');
	put_file $top->path("standalone.yml"), <<EOF;
---
kit:
  name:    bosh
  version: 0.2.0
  features:
    - vsphere
    - proto

genesis: {}

params:
  state:   awesome
  running: yes
  false:   ~
EOF

	my $env = $top->load_env('standalone');
	is($env->name, "standalone", "an environment should know its name");
	is($env->file, "standalone.yml", "an environment should know its file path");
	is($env->deployment_name, "standalone-thing", "an environment should know its deployment name");
	is($env->kit->id, "bosh/0.2.0", "an environment can ask the kit for its kit name/version");
	is($env->secrets_mount, '/secret/', "default secret mount used when none provided");
	is($env->secrets_slug, 'standalone/thing', "default secret slug generated correctly");
	is($env->secrets_base, '/secret/standalone/thing/', "default secret base path generated correctly");
	is($env->exodus_mount, '/secret/exodus/', "default exodus mount used when none provided");
	is($env->exodus_base, '/secret/exodus/standalone/thing', "correctly evaluates exodus base path");
	is($env->ci_mount, '/secret/ci/', "default ci mount used when none provided");
	is($env->ci_base, '/secret/ci/thing/standalone/', "correctly evaluates ci base path");

	put_file $top->path("standalone-with-another.yml"), <<EOF;
---
kit:
  features:
    - ((append))
    - extras

genesis:
  secrets_mount: genesis/secrets
  exodus_mount:  genesis/exodus
EOF
	local $ENV{NOCOLOR} = 'y';
	throws_ok { $env = $top->load_env('standalone-with-another.yml');} 
		qr/\[ERROR\] Environment standalone-with-another.yml could not be loaded:\n\s+- Kit bosh\/0.2.0 is not compatible with secrets_mount feature\n\s+Please upgrade to a newer release or remove genesis.secrets_mount from standalone-with-another.yml\n\s+- Kit bosh\/0.2.0 is not compatible with exodus_mount feature\n\s+Please upgrade to a newer release or remove genesis.exodus_mount from standalone-with-another.yml/ms,
		"Outdated kits bail when using v2.7.0 features";

=comment
	# This needs a kit that is v2.7.0 compatible
	put_file $top->path("standalone-with-another.yml"), <<EOF;
---
kit:
  features:
    - ((append))
    - extras

genesis:
  secrets_mount: genesis/secrets
  exodus_mount:  genesis/exodus
EOF
	$env = $top->load_env('standalone-with-another.yml');
	is($env->name, "standalone-with-another", "an environment should know its name");
	is($env->file, "standalone-with-another.yml", "an environment should know its file path");
	is($env->deployment_name, "standalone-with-another-thing", "an environment should know its deployment name");
	is($env->kit->id, "bosh/0.2.0", "an environment can inherit its kit name/version");
	is($env->secrets_mount, '/genesis/secrets/', "specified secret mount used when  provided");
	is($env->secrets_slug, 'standalone/with/another/thing', "default secret slug generated correctly");
	is($env->secrets_base, '/genesis/secrets/standalone/with/another/thing/', "default secret base path generated correctly");
	is($env->exodus_mount, '/genesis/exodus/', "specified exodus mount used when provided");
	is($env->exodus_base, '/genesis/exodus/standalone-with-another/thing/', "correctly evaluates exodus base path");
	is($env->ci_mount, '/genesis/secrets/ci/', "default ci mount used when none provided but secrets_mount is");
	is($env->ci_base, '/genesis/secrets/ci/thing/standalone-with-another/', "correctly evaluates ci base path");
=cut

	teardown_vault();

};

subtest 'parameter lookup' => sub {
	my $vault_target = vault_ok;
	Genesis::Vault->clear_all();
	my $top = Genesis::Top->create(workdir, 'thing', vault=>$VAULT_URL);
	$top->download_kit('bosh/0.2.0');
	put_file $top->path("standalone.yml"), <<EOF;
---
kit:
  name:    bosh
  version: 0.2.0
  features:
    - vsphere
    - second-feature

genesis: {}

params:
  state:   awesome
  running: yes
  false:   ~
EOF

	my $env;
	$ENV{NOCOLOR}=1;
	throws_ok { $top->load_env('enoent');   } qr/enoent.yml does not exist/;
	throws_ok { $top->load_env('e-no-ent'); } qr/does not exist/;

	lives_ok { $env = $top->load_env('standalone') }
	         "Genesis::Env should be able to load the `standalone' environment.";

	ok($env->defines('params.state'), "standalone.yml should define params.state");
	is($env->lookup('params.state'), "awesome", "params.state in standalone.yml should be 'awesome'");
	ok($env->defines('params.false'), "params with falsey values should still be considered 'defined'");
	ok(!$env->defines('params.enoent'), "standalone.yml should not define params.enoent");
	is($env->lookup('params.enoent', 'MISSING'), 'MISSING',
		"params lookup should return the default value is the param is not defined");
	is($env->lookup('params.false', 'MISSING'), undef,
		"params lookup should return falsey values if they are set");

	cmp_deeply([$env->features], [qw[vsphere second-feature]],
		"features() returns the current features");
	ok($env->has_feature('vsphere'), "standalone env has the vsphere feature");
	ok($env->has_feature('second-feature'), "standalone env has the second-feature feature");
	ok(!$env->has_feature('xyzzy'), "standalone env doesn't have the xyzzy feature");
	ok($env->use_create_env(),
		"bosh environments without specifying bosh_env require bosh create-env");

	put_file $top->path("regular-deploy.yml"), <<EOF;
---
kit:
  name:    bosh
  version: 0.2.0
  features:
    - vsphere

genesis:
  bosh_env: parent-bosh
EOF
	lives_ok { $env = $top->load_env('regular-deploy') }
	         "Genesis::Env should be able to load the `regular-deploy' environment.";
	ok($env->has_feature('vsphere'), "regular-deploy env has the vsphere feature");
	ok(!$env->use_create_env(),
		"bosh environments with genesis.bosh_env set do not require bosh create-env");

	teardown_vault();
};

subtest 'manifest generation' => sub {
	my $vault_target = vault_ok;
	Genesis::Vault->clear_all();
	write_bosh_config 'standalone';
	my $top = Genesis::Top->create(workdir, 'thing', vault=>$VAULT_URL);
	$top->link_dev_kit('t/src/fancy');
	put_file $top->path('standalone.yml'), <<EOF;
---
kit:
  name:    dev
  version: latest
  features:
    - whiskey
    - tango
    - foxtrot

genesis: {}
EOF

	my $env = $top->load_env('standalone');
	cmp_deeply([$env->kit_files], [qw[
		base.yml
		addons/whiskey.yml
		addons/tango.yml
		addons/foxtrot.yml
	]], "env gets the correct kit yaml files to merge");
	cmp_deeply([$env->potential_environment_files], [qw[
		./standalone.yml
	]], "env formulates correct potential environment files to merge");
	cmp_deeply([$env->actual_environment_files], [qw[
		./standalone.yml
	]], "env detects correct actual environment files to merge");

	dies_ok { $env->manifest; } "should not be able to merge an env without a cloud-config";


	put_file $top->path(".cloud.yml"), <<EOF;
--- {}
# not really a cloud config, but close enough
EOF
	lives_ok { $env->use_config($top->path(".cloud.yml"))->manifest; }
		"should be able to merge an env with a cloud-config";

	my $mfile = $top->path(".manifest.yml");
	my ($manifest, undef) = $env->_manifest(redact => 0);
	$env->write_manifest($mfile, prune => 0);
	ok -f $mfile, "env->write_manifest should actually write the file";
	my $mcontents;
	lives_ok { $mcontents = load_yaml_file($mfile) } 'written manifest (unpruned) is valid YAML';
	cmp_deeply($mcontents, $manifest, "written manifest (unpruned) matches the raw unpruned manifest");
	cmp_deeply($mcontents, {
		name   => ignore,
		fancy  => ignore,
		addons => ignore,
		exodus => ignore,
		genesis=> ignore,
		kit    => ignore,
		meta   => ignore,
		params => ignore
	}, "written manifest (unpruned) contains all the keys");

	ok $env->manifest_lookup('addons.foxtrot'), "env manifest defines addons.foxtrot";
	is $env->manifest_lookup('addons.bravo', 'MISSING'), 'MISSING',
		"env manifest doesn't define addons.bravo";

	teardown_vault();
};

subtest 'manifest pruning' => sub {
	my $vault_target = vault_ok;
	Genesis::Vault->clear_all();
	my $top = Genesis::Top->create(workdir, 'thing', vault=>$VAULT_URL);
	$top->link_dev_kit('t/src/fancy');
	put_file $top->path(".cloud.yml"), <<EOF;
---
resource_pools: { from: 'cloud-config' }
vm_types:       { from: 'cloud-config' }
disk_pools:     { from: 'cloud-config' }
disk_types:     { from: 'cloud-config' }
networks:       { from: 'cloud-config' }
azs:            { from: 'cloud-config' }
vm_extensions:  { from: 'cloud-config' }
compilation:    { from: 'cloud-config' }
EOF

	put_file $top->path('standalone.yml'), <<EOF;
---
kit:
  name:    dev
  version: latest
  features:
    - papa    # for pruning tests
genesis: {}
EOF
	my $env = $top->load_env('standalone')->use_config($top->path('.cloud.yml'));

	cmp_deeply(scalar load_yaml($env->manifest(prune => 0)), {
		name   => ignore,
		fancy  => ignore,
		addons => ignore,

		# Genesis stuff
		meta        => ignore,
		pipeline    => ignore,
		params      => ignore,
		exodus      => ignore,
		genesis     => ignore,
		kit         => superhashof({ name => 'dev' }),

		# cloud-config
		resource_pools => ignore,
		vm_types       => ignore,
		disk_pools     => ignore,
		disk_types     => ignore,
		networks       => ignore,
		azs            => ignore,
		vm_extensions  => ignore,
		compilation    => ignore,

	}, "unpruned manifest should have all the top-level keys");

	cmp_deeply(scalar load_yaml($env->manifest(prune => 1)), {
		name   => ignore,
		fancy  => ignore,
		addons => ignore,
	}, "pruned manifest should not have all the top-level keys");

	my $mfile = $top->path(".manifest.yml");
	my ($manifest, undef) = $env->_manifest(redact => 0);
	$env->write_manifest($mfile);
	ok -f $mfile, "env->write_manifest should actually write the file";
	my $mcontents;
	lives_ok { $mcontents = load_yaml_file($mfile) } 'written manifest is valid YAML';
	cmp_deeply($mcontents, subhashof($manifest), "written manifest content matches unpruned manifest for values that weren't pruned");
	cmp_deeply($mcontents, {
		name   => ignore,
		fancy  => ignore,
		addons => ignore,
	}, "written manifest doesn't contain the pruned keys (no cloud-config)");
	teardown_vault();
};

subtest 'manifest pruning (custom bosh create-env)' => sub {
	my $vault_target = vault_ok;
	Genesis::Vault->clear_all();
	my $top = Genesis::Top->create(workdir, 'thing', vault=>$VAULT_URL);
	$top->link_dev_kit('t/src/custom-bosh');
	put_file $top->path(".cloud.yml"), <<EOF;
---
ignore: cloud-config
EOF

	# create-env
	put_file $top->path('proto.yml'), <<EOF;
---
kit:
  name:    dev
  version: latest
  features:
    - papa     # for pruning tests
genesis: {}
EOF
	my $env = $top->load_env('proto')->use_config($top->path('.cloud.yml'));
	ok $env->use_create_env, "'proto' test env needs create-env";
	cmp_deeply(scalar load_yaml($env->manifest(prune => 0)), {
		name   => ignore,
		fancy  => ignore,
		addons => ignore,

		# Genesis stuff
		meta        => ignore,
		pipeline    => ignore,
		params      => ignore,
		exodus      => ignore,
		genesis     => ignore,
		kit         => superhashof({ name => 'dev' }),

		# BOSH stuff
		compilation => ignore,

		# "cloud-config"
		resource_pools => ignore,
		vm_types       => ignore,
		disk_pools     => ignore,
		disk_types     => ignore,
		networks       => ignore,
		azs            => ignore,
		vm_extensions  => ignore,

	}, "unpruned proto-style manifest should have all the top-level keys");

	cmp_deeply(scalar load_yaml($env->manifest(prune => 1)), {
		name   => ignore,
		fancy  => ignore,
		addons => ignore,

		# "cloud-config"
		resource_pools => ignore,
		vm_types       => ignore,
		disk_pools     => ignore,
		disk_types     => ignore,
		networks       => ignore,
		azs            => ignore,
		vm_extensions  => ignore,
	}, "pruned proto-style manifest should retain 'cloud-config' keys, since create-env needs them");

	my $mfile = $top->path(".manifest-create-env.yml");
	my ($manifest, undef) = $env->_manifest(redact => 0);
	$env->write_manifest($mfile);
	ok -f $mfile, "env->write_manifest should actually write the file";
	my $mcontents;
	lives_ok { $mcontents = load_yaml_file($mfile) } 'written manifest for bosh-create-env is valid YAML';
	cmp_deeply($mcontents, subhashof($manifest), "written manifest for bosh-create-env content matches unpruned manifest for values that weren't pruned");
	cmp_deeply($mcontents, {
		name   => ignore,
		fancy  => ignore,
		addons => ignore,

		# "cloud-config"
		resource_pools => ignore,
		vm_types       => ignore,
		disk_pools     => ignore,
		disk_types     => ignore,
		networks       => ignore,
		azs            => ignore,
		vm_extensions  => ignore,
	}, "written manifest for bosh-create-env doesn't contain the pruned keys (includes cloud-config)");

	teardown_vault();
};

subtest 'exodus data' => sub {
	my $vault_target = vault_ok;
	Genesis::Vault->clear_all();
	my $top = Genesis::Top->create(workdir, 'thing', vault=>$VAULT_URL);
	$top->link_dev_kit('t/src/fancy');
	put_file $top->path('standalone.yml'), <<EOF;
---
kit:
  name:    dev
  version: latest
  features:
    - echo    # for pruning tests
genesis: {}
EOF
	put_file $top->path(".cloud.yml"), <<EOF;
--- {}
# not really a cloud config, but close enough
EOF

	my $env = $top->load_env('standalone')->use_config($top->path('.cloud.yml'));
	cmp_deeply($env->exodus, {
			version       => ignore,
			dated         => re(qr/\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/),
			deployer      => ignore,
			kit_name      => 'fancy',
			kit_version   => '0.0.0-rc0',
			kit_is_dev    => JSON::PP::true,
			'addons[0]'   => 'echo',
			vault_base    => '/secret/standalone/thing',
			features      => 'echo',

			'hello.world' => 'i see you',

			# we allow multi-level arrays now
			'multilevel.arrays[0]' => 'so',
			'multilevel.arrays[1]' => 'useful',

			# we allow multi-level maps now
			'three.levels.works'            => 'now',
			'three.levels.or.more.is.right' => 'on, man!',
		}, "env manifest can provide exodus with flattened keys");

	my $good_flattened = {
		key => "value",
		another_key => "another value",

		# flattened hash
		'this.is.a.test' => '100%',
		'this.is.a.dog'  => 'woof',
		'this.is.sparta' => 300,

		# flattened array
		'matrix[0][0]' => -2,
		'matrix[0][1]' =>  4,
		'matrix[1][0]' =>  2,
		'matrix[1][1]' => -4,

		# flattened array of hashes
		'network[0].name' => 'default',
		'network[0].subnet' => '10.0.0.0/24',
		'network[1].name' => 'super-special',
		'network[1].subnet' => '10.0.1.0/24',
		'network[2].name' => 'secret',
		'network[2].subnet' => '10.0.2.0/24',
	};


	cmp_deeply(Genesis::Env::_unflatten($good_flattened), {
		key => "value",
		another_key => "another value",
		this => {
			is => {
				a => {
					test => '100%',
					dog  => 'woof',
				},
				sparta => 300,
			}
		},
		matrix => [
			[-2, 4],
			[ 2,-4]
		],
		network => [
			{
				name => 'default',
				subnet => '10.0.0.0/24',
			}, {
				name => 'super-special',
				subnet => '10.0.1.0/24',
			}, {
				name => 'secret',
				subnet => '10.0.2.0/24',
			}
		]
	}, "exodus data can be correctly unflattened");

	teardown_vault();
};

subtest 'cloud_config_and_deployment' => sub{
	local $ENV{GENESIS_BOSH_COMMAND};
	my ($director1) = fake_bosh_directors(
		{alias => 'standalone'},
	);
	fake_bosh;
	my $vault_target = vault_ok;
	Genesis::Vault->clear_all();
	`safe set --quiet secret/code word='penguin'`;

	my $top = Genesis::Top->create(workdir, 'thing', vault=>$VAULT_URL)->link_dev_kit('t/src/fancy');
	put_file $top->path('standalone.yml'), <<EOF;
---
kit:
  name:    dev
  version: latest
EOF

	Genesis::BOSH->set_command($ENV{GENESIS_BOSH_COMMAND});
	my $env = $top->load_env('standalone');
	lives_ok { $env->download_configs('cloud'); }
		"download_cloud_config runs correctly";

	ok -f $env->config_file('cloud'), "download_cloud_config created cc file";
	eq_or_diff get_file($env->config_file('cloud')), <<EOF, "download_config calls BOSH correctly";
{"cmd": "bosh config --type cloud --name default --json"}
EOF

	put_file $env->config_file('cloud'), <<EOF;
---
something: (( vault "secret/code:word" ))
EOF

	is($env->lookup("something","goose"), "goose", "Environment doesn't contain cloud config details");
	is($env->manifest_lookup("something","goose"), "penguin", "Manifest contains cloud config details");
	my ($manifest_file, $exists, $sha1) = $env->cached_manifest_info;
	ok $manifest_file eq $env->path(".genesis/manifests/".$env->name.".yml"), "cached manifest path correctly determined";
	ok ! $exists, "manifest file doesn't exist.";
	ok ! defined($sha1), "sha1 sum for manifest not computed.";
	stdout_is(sub {$env->deploy()}, <<EOF,
bosh
deploy
--no-redact
$env->{__tmp}/manifest.yml

Deployment successful.  Preparing metadata for export...
Done.

EOF
		"Deploy should call BOSH with the correct options");

	($manifest_file, $exists, $sha1) = $env->cached_manifest_info;
	ok $manifest_file eq $env->path(".genesis/manifests/".$env->name.".yml"), "cached manifest path correctly determined";
	ok $exists, "manifest file should exist.";
	ok $sha1 =~ /[a-f0-9]{40}/, "cached manifest calculates valid SHA-1 checksum";
	ok -f $manifest_file, "deploy created cached redacted manifest file";

	# Compare the raw exodus data
	#
	runs_ok('safe exists "secret/exodus/standalone/thing"', 'exodus entry created in vault');
	my ($pass, $rc, $out) = runs_ok('safe get "secret/exodus/standalone/thing" | spruce json #');
	my $exodus = load_json($out);
	local %ENV = %ENV;
	$ENV{USER} ||= 'unknown';
	cmp_deeply($exodus, {
				dated => re(qr/\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d \+0000/),
				deployer => $ENV{USER},
				kit_name => "fancy",
				kit_version => "0.0.0-rc0",
				kit_is_dev => 1,
				features => '',
				bosh => "standalone",
				is_bosh => 0,
				vault_base => "/secret/standalone/thing",
				version => '(development)',
				manifest_sha1 => $sha1,
				'hello.world' => 'i see you',
				'multilevel.arrays[0]' => 'so',
				'multilevel.arrays[1]' => 'useful',
				'three.levels.or.more.is.right' => 'on, man!',
				'three.levels.works' => 'now'
			}, "exodus data was written by deployment");

	is($env->last_deployed_lookup("something","goose"), "REDACTED", "Cached manifest contains redacted vault details");
	is($env->last_deployed_lookup("fancy.status","none"), "online", "Cached manifest contains non-redacted params");
	is($env->last_deployed_lookup("genesis.env","none"), "standalone", "Cached manifest contains pruned params");
	cmp_deeply(scalar($env->exodus_lookup("",{})), {
				dated => $exodus->{dated},
				deployer => $ENV{USER},
				bosh => "standalone",
				is_bosh => 0,
				kit_name => "fancy",
				kit_version => "0.0.0-rc0",
				kit_is_dev => 1,
				features => '',
				vault_base => "/secret/standalone/thing",
				version => '(development)',
				manifest_sha1 => $sha1,
				hello => {
					world => 'i see you'
				},
				multilevel => {
					arrays => ['so','useful']
				},
				three => {
					levels => {
						'or'    => { more => {is => {right => 'on, man!'}}},
						'works' => 'now'
					}
				}
			}, "exodus data was written by deployment");

	$director1->stop();
	teardown_vault();
};
subtest 'bosh variables' => sub {
	local $ENV{GENESIS_BOSH_COMMAND};
	fake_bosh;

	my ($director1) = fake_bosh_directors(
		{alias => 'standalone'},
	);
	my $vault_target = vault_ok;
	Genesis::Vault->clear_all();
	Genesis::BOSH->set_command($ENV{GENESIS_BOSH_COMMAND});
	my $top = Genesis::Top->create(workdir, 'thing', vault=>$VAULT_URL)->link_dev_kit('t/src/fancy');
	put_file $top->path("standalone.yml"), <<EOF;
---
kit:
  name:    dev
  version: latest
  features: []

bosh-variables:
  something:       valueable
  cc:              (( grab cc-stuff ))
  collection:      (( join " " params.extras ))
  deployment_name: (( grab name ))

params:
  extras:
    - 1
    - 2
    - 3

EOF
	my $env = $top->load_env('standalone');
	lives_ok { $env->download_configs('cloud'); }
		"download_cloud_config runs correctly";

	put_file $env->config_file('cloud'), <<EOF;
---
cc-stuff: cloud-config-data
EOF

	my $varsfile = $env->vars_file();
	stdout_is(sub {$env->deploy()}, <<EOF, "Deploy should call BOSH with the correct options, including vars file");
bosh
deploy
--no-redact
-l
$varsfile
$env->{__tmp}/manifest.yml

Deployment successful.  Preparing metadata for export...
Done.

EOF

	eq_or_diff get_file($env->vars_file), <<EOF, "download_cloud_config calls BOSH correctly";
cc: cloud-config-data
collection: 1 2 3
deployment_name: standalone-thing
something: valueable

EOF

	teardown_vault();
};

subtest 'new env and check' => sub{
	local $ENV{GENESIS_BOSH_COMMAND};
	my $vault_target = vault_ok;
	Genesis::Vault->clear_all();

	my $name = "far-fetched";
	write_bosh_config $name;
	my $top = Genesis::Top->create(workdir, 'sample', vault=>$VAULT_URL);
	my $kit = $top->link_dev_kit('t/src/creator')->local_kit_version('dev');
	mkfile_or_fail $top->path("pre-existing.yml"), "I'm already here";

	# create the environment
	dies_ok {$top->create_env('', $kit)} "can't create a unnamed env";
	dies_ok {$top->create_env("nothing")} "can't create a env without a kit";
	dies_ok {$top->create_env("pre-existing", $kit)} "can't overwrite a pre-existing env";

	my $env;
	local $ENV{NOCOLOR} = "yes";
	local $ENV{PRY} = "1";
	my ($director1) = fake_bosh_directors(
		{alias => $name},
	);
	fake_bosh;
	Genesis::BOSH->set_command($ENV{GENESIS_BOSH_COMMAND});
	my $out;
	lives_ok {
		$out = combined_from {$env = $top->create_env($name, $kit, vault => $vault_target)}
	} "successfully create an env with a dev kit";

	$out =~ s/(Duration:|-) (\d+ minutes, )?\d+ seconds?/$1 XXX seconds/g;
	eq_or_diff $out, <<EOF, "creating environment provides secret generation output";
Parsing kit secrets descriptions ... done. - XXX seconds

Adding 10 secrets for far-fetched under path '/secret/far/fetched/sample/':
  [ 1/10] my-cert/ca X509 certificate - CA, self-signed ... done.
  [ 2/10] my-cert/server X509 certificate - signed by 'my-cert/ca' ... done.
  [ 3/10] ssl/ca X509 certificate - CA, self-signed ... done.
  [ 4/10] ssl/server X509 certificate - signed by 'ssl/ca' ... done.
  [ 5/10] crazy/thing:id random password - 32 bytes, fixed ... done.
  [ 6/10] crazy/thing:token random password - 16 bytes ... done.
  [ 7/10] users/admin:password random password - 64 bytes ... done.
  [ 8/10] users/bob:password random password - 16 bytes ... done.
  [ 9/10] work/signing_key RSA public/private keypair - 2048 bits, fixed ... done.
  [10/10] something/ssh SSH public/private keypair - 2048 bits, fixed ... done.
Completed - Duration: XXX seconds [10 added/0 skipped/0 errors]

EOF

	eq_or_diff get_file($env->path($env->{file})), <<EOF, "Created env file contains correct info";
---
kit:
  name:    dev
  version: latest
  features:
    - (( replace ))
    - bonus

params:
  static: junk
EOF

	$out = combined_from {
		ok $env->check_secrets(verbose => 1), "check_secrets shows all secrets okay"
	};
	$out =~ s/(Duration:|-) (\d+ minutes, )?\d+ seconds?/$1 XXX seconds/g;

	eq_or_diff $out, <<EOF, "check_secrets gives meaninful output on success";
Parsing kit secrets descriptions ... done. - XXX seconds
Retrieving all existing secrets ... done. - XXX seconds

Checking 10 secrets for far-fetched under path '/secret/far/fetched/sample/':
  [ 1/10] my-cert/ca X509 certificate - CA, self-signed ... found.
  [ 2/10] my-cert/server X509 certificate - signed by 'my-cert/ca' ... found.
  [ 3/10] ssl/ca X509 certificate - CA, self-signed ... found.
  [ 4/10] ssl/server X509 certificate - signed by 'ssl/ca' ... found.
  [ 5/10] crazy/thing:id random password - 32 bytes, fixed ... found.
  [ 6/10] crazy/thing:token random password - 16 bytes ... found.
  [ 7/10] users/admin:password random password - 64 bytes ... found.
  [ 8/10] users/bob:password random password - 16 bytes ... found.
  [ 9/10] work/signing_key RSA public/private keypair - 2048 bits, fixed ... found.
  [10/10] something/ssh SSH public/private keypair - 2048 bits, fixed ... found.
Completed - Duration: XXX seconds [10 found/0 skipped/0 errors]

EOF

	qx(safe export > /tmp/out.json);

	qx(safe rm -rf secret/far/fetched/sample/users);
	qx(safe rm secret/far/fetched/sample/ssl/ca:key secret/far/fetched/sample/ssl/ca:certificate);
	qx(safe rm secret/far/fetched/sample/crazy/thing:token);

	$out = combined_from {
		ok !$env->check_secrets(verbose=>1), "check_secrets shows missing secrets and keys"
	};
	$out =~ s/(Duration:|-) (\d+ minutes, )?\d+ seconds?/$1 XXX seconds/g;

	matches_utf8 $out, <<EOF,  "check_secrets gives meaninful output on failure";
Parsing kit secrets descriptions ... done. - XXX seconds
Retrieving all existing secrets ... done. - XXX seconds

Checking 10 secrets for far-fetched under path '/secret/far/fetched/sample/':
  [ 1/10] my-cert/ca X509 certificate - CA, self-signed ... found.
  [ 2/10] my-cert/server X509 certificate - signed by 'my-cert/ca' ... found.
  [ 3/10] ssl/ca X509 certificate - CA, self-signed ... missing!
          [✘ ] missing key ':certificate'
          [✘ ] missing key ':key'

  [ 4/10] ssl/server X509 certificate - signed by 'ssl/ca' ... found.
  [ 5/10] crazy/thing:id random password - 32 bytes, fixed ... found.
  [ 6/10] crazy/thing:token random password - 16 bytes ... missing!
  [ 7/10] users/admin:password random password - 64 bytes ... missing!
  [ 8/10] users/bob:password random password - 16 bytes ... missing!
  [ 9/10] work/signing_key RSA public/private keypair - 2048 bits, fixed ... found.
  [10/10] something/ssh SSH public/private keypair - 2048 bits, fixed ... found.
Failed - Duration: XXX seconds [6 found/0 skipped/4 errors]

EOF

	$director1->stop();
	teardown_vault();
};

done_testing;
