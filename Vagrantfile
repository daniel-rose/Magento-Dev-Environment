Vagrant.configure(2) do |config|
  config.vm.box = "ubuntu/trusty32"
  config.vm.provision :shell, path: "bootstrap.sh"
  config.vm.network :forwarded_port, guest: 80, host: 8080, auto_correct: true
  config.vm.network :forwarded_port, guest: 9000, host: 9000, auto_correct: true
  config.vm.synced_folder ".", "/vagrant", disabled: true

  config.ssh.forward_agent = true

  config.vm.provider :virtualbox do |vb|
    vb.customize ["modifyvm", :id, "--memory", "1024"]
    vb.name = "Simple Magento Dev Environment"
  end
end
