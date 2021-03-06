require 'spec_helper'
describe 'nfsclient' do
  let :facts do
    {}
  end

  let :params do
    {}
  end

  let :options do
    {
      'gss_line' =>
        {
          'RedHat' => 'SECURE_NFS',
          'Suse' => 'NFS_SECURITY_GSS',
        },
      'keytab_line' =>
        {
          'RedHat' => 'RPCGSSDARGS',
          'Suse' => 'GSSD_OPTIONS',
        },
    }
  end

  context 'generic config' do
    on_supported_os.each do |os, facts|
      context "on os #{os}" do

        let(:facts) do
          facts
        end
        # lsbmajdistrelease does not exist in facterdb 0.3.0
        facts.merge!({:lsbmajdistrelease => facts[:operatingsystemrelease].split('.')[0]})

        it 'should not do anything by default' do
          should compile
          should have_resource_count(0)
        end

        it 'should configure gss if specified' do
          params.merge!({'gss' => true})
          should contain_file_line('NFS_SECURITY_GSS').with(
          {
            'path' => '/etc/sysconfig/nfs',
            'line' => "#{options['gss_line'][facts[:osfamily]]}=\"yes\"",
            'match' => "^#{options['gss_line'][facts[:osfamily]]}=.*",
          })
          should contain_file_line('NFS_SECURITY_GSS').that_notifies('Service[rpcbind_service]')
          should contain_class('rpcbind')
          should contain_class('nfs::idmap')
        end

        it 'should configure keytab if specified' do
          params.merge!({'gss' => true, 'keytab' => '/etc/keytab'})
          should contain_file_line('GSSD_OPTIONS').with(
          {
            'path' => '/etc/sysconfig/nfs',
            'line' => "#{options['keytab_line'][facts[:osfamily]]}=\"-k /etc/keytab\"",
            'match' => "^#{options['keytab_line'][facts[:osfamily]]}=.*",
          })
          should contain_file_line('GSSD_OPTIONS').that_notifies('Service[rpcbind_service]')
        end

      end
    end
  end

  context 'specific config for SLES 11' do
    let :facts do
      {
        'osfamily'               => 'Suse',
        'lsbmajdistrelease'      => '11',
        'operatingsystemrelease' => '11.0',
      }
    end

    it 'should configure gssd and idmapd on SUSE 11' do
      params.merge!({'gss' => true})
      should contain_file_line('NFS_START_SERVICES').with(
      {
        'path' => '/etc/sysconfig/nfs',
        'line' => 'NFS_START_SERVICES="yes"',
        'match' => '^NFS_START_SERVICES=',
        'notify' => ['Service[nfs]', 'Service[rpcbind_service]'],
      })
      should contain_file_line('MODULES_LOADED_ON_BOOT').with(
      {
        'path' => '/etc/sysconfig/kernel',
        'line' => 'MODULES_LOADED_ON_BOOT="rpcsec_gss_krb5"',
        'match' => '^MODULES_LOADED_ON_BOOT=',
        'notify' => 'Exec[gss-module-modprobe]',
      })
      should contain_exec('gss-module-modprobe').with(
      {
        'command' => 'modprobe rpcsec_gss_krb5',
        'unless' => 'lsmod | egrep "^rpcsec_gss_krb5"',
        'path' => '/sbin:/usr/bin',
        'refreshonly' => true,
      })
    end

    it 'should configure keytab on SUSE 11' do
      params.merge!({'gss' => true, 'keytab' => '/etc/keytab'})
      should contain_file_line('GSSD_OPTIONS').that_notifies('Service[nfs]')
    end

    it 'should manage nfs on SUSE 11' do
      params.merge!({'gss' => true})
      should contain_service('nfs').with(
      {
        'ensure'  => 'running',
        'enable'  => 'true',
      })
      should contain_file_line('NFS_SECURITY_GSS').that_notifies('Service[nfs]')
      is_expected.not_to contain_service('nfs').that_requires('Service[idmapd_service]')
    end
  end

  context 'specific config for SLES 12' do
    let :facts do
      {
        'osfamily'               => 'Suse',
        'lsbmajdistrelease'      => '12',
        'operatingsystemrelease' => '12',
      }
    end

    it 'should configure keytab on SUSE 12' do
      params.merge!({'gss' => true, 'keytab' => '/etc/keytab'})
      should contain_file_line('GSSD_OPTIONS').that_notifies('Service[nfs]')
    end

    it 'should manage nfs on SUSE 12' do
      params.merge!({'gss' => true})
      facts.merge!('lsbmajdistrelease' => '12')
      should contain_service('nfs').with(
      {
        'ensure' => 'running',
        'enable' => 'true',
      })
      should contain_file_line('NFS_SECURITY_GSS').that_notifies('Service[nfs]')
      is_expected.not_to contain_service('nfs').that_requires('Service[idmapd_service]')
    end
  end

  context 'specific config for RHEL' do
    let :facts do
      {
        'osfamily'                  => 'RedHat',
        'operatingsystemrelease'    => '6.7',
        'operatingsystemmajrelease' => '6',
      }
    end

    it 'should manage rpcgssd' do
      params.merge!({'gss' => true})
      should contain_service('rpcgssd').with(
      {
        'ensure' => 'running',
        'enable' => true,
      })
      should contain_file_line('NFS_SECURITY_GSS').that_notifies('Service[rpcgssd]')
    end
  end

  context 'specific config for RHEL 7' do
    let :facts do
      {
        'osfamily'                  => 'RedHat',
        'operatingsystemrelease'    => '7.2',
        'operatingsystemmajrelease' => '7',
      }
    end

    it 'should manage keytab' do
      params.merge!({'gss' => true, 'keytab' => '/etc/keytab'})

      should contain_service('nfs-config').with(
        'ensure' => 'running',
        'enable' => true
      )
      should contain_service('nfs-config').that_subscribes_to('File_line[GSSD_OPTIONS]')

      should contain_file('/etc/krb5.keytab').with(
        'ensure' => 'symlink',
        'target' => '/etc/opt/quest/vas/host.keytab'
      )
      should contain_file('/etc/krb5.keytab').that_notifies('Service[rpcgssd]')

      is_expected.to contain_service('nfs-config').that_notifies('Service[rpcgssd]')
      is_expected.to contain_service('rpcbind_service').that_comes_before('Service[rpcgssd]')
      is_expected.to contain_service('rpcgssd').that_requires('Service[idmapd_service]')
    end
  end

  context 'on unsupported os' do
    it 'should fail gracefully' do
      facts.merge!('osfamily' => 'UNSUPPORTED')
      should compile.and_raise_error(/nfsclient module only supports Suse and RedHat. <UNSUPPORTED> was detected./)
    end
  end

  describe 'variable type and content validations' do
    # set needed custom facts and variables
    let(:facts) do
      {
        :osfamily                  => 'RedHat',
        :operatingsystemrelease    => '7.2',
        :operatingsystemmajrelease => '7',
      }
    end
    let(:mandatory_params) do
      {
        #:param => 'value',
      }
    end

    validations = {
      'absolute_path' => {
        :name    => %w(keytab),
        :valid   => ['/absolute/filepath','/absolute/directory/'],
        :invalid => ['string', %w(array), { 'ha' => 'sh' }, 3, 2.42, true, false, nil],
        :message => 'is not an absolute path',
      },
      'boolean_stringified' => {
        :name    => %w(gss),
        :valid   => [true, false, 'true', 'false'],
        :invalid => ['string', %w(array), { 'ha' => 'sh' }, 3, 2.42, nil],
        :message => 'str2bool',
      },
    }

    validations.sort.each do |type, var|
      var[:name].each do |var_name|
        var[:params] = {} if var[:params].nil?
        var[:valid].each do |valid|
          context "when #{var_name} (#{type}) is set to valid #{valid} (as #{valid.class})" do
            let(:params) { [mandatory_params, var[:params], { :"#{var_name}" => valid, }].reduce(:merge) }
            it { should compile }
          end
        end

        var[:invalid].each do |invalid|
          context "when #{var_name} (#{type}) is set to invalid #{invalid} (as #{invalid.class})" do
            let(:params) { [mandatory_params, var[:params], { :"#{var_name}" => invalid, }].reduce(:merge) }
            it 'should fail' do
              expect { should contain_class(subject) }.to raise_error(Puppet::Error, /#{var[:message]}/)
            end
          end
        end
      end # var[:name].each
    end # validations.sort.each
  end # describe 'variable type and content validations'

end
