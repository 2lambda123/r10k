require 'spec_helper'
require 'r10k/git'
require 'r10k/git/stateful_repository'

describe R10K::Git::StatefulRepository do
  include_context 'Git integration'

  let(:dirname) { 'working-repo' }

  let(:cacherepo) { R10K::Git.cache.generate(remote) }
  let(:thinrepo) { R10K::Git.thin_repository.new(basedir, dirname, cacherepo) }
  let(:ref) { '0.9.x' }

  subject { described_class.new(remote, basedir, dirname) }

  describe 'status' do
    describe "when the directory does not exist" do
      it "is absent" do
        expect(subject.status(ref)).to eq :absent
      end
    end

    describe "when the directory is not a git repository" do
      it "is mismatched" do
        thinrepo.path.mkdir
        expect(subject.status(ref)).to eq :mismatched
      end
    end

    describe "when the directory has a .git file" do
      it "is mismatched" do
        thinrepo.path.mkdir
        File.open("#{thinrepo.path}/.git", "w") {}
        expect(subject.status(ref)).to eq :mismatched
      end
    end

    describe "when the repository doesn't match the desired remote" do
      it "is mismatched" do
        thinrepo.clone(remote, {:ref => '1.0.0'})
        allow(subject.repo).to receive(:origin).and_return('http://some.site/repo.git')
        expect(subject.status(ref)).to eq :mismatched
      end
    end

    describe "when the wrong ref is checked out" do
      it "is outdated" do
        thinrepo.clone(remote, {:ref => '1.0.0'})
        expect(subject.status(ref)).to eq :outdated
      end
    end

    describe "when the ref is a branch and the cache is not synced" do
      it "is outdated" do
        thinrepo.clone(remote, {:ref => ref})
        cacherepo.reset!
        expect(subject.status(ref)).to eq :outdated
      end
    end

    describe "when the ref can't be resolved" do
      let(:ref) { '1.1.x' }

      it "is outdated" do
        thinrepo.clone(remote, {:ref => '0.9.x'})
        expect(subject.status(ref)).to eq :outdated
      end
    end

    describe "when the workdir has local modifications" do
      it "is dirty when workdir is up to date" do
        thinrepo.clone(remote, {:ref => ref})
        File.open(File.join(thinrepo.path, 'README.markdown'), 'a') { |f| f.write('local modifications!') }

        expect(subject.status(ref)).to eq :dirty
      end

      it "is dirty when workdir is not up to date" do
        thinrepo.clone(remote, {:ref => '1.0.0'})
        File.open(File.join(thinrepo.path, 'README.markdown'), 'a') { |f| f.write('local modifications!') }

        expect(subject.status(ref)).to eq :dirty
      end
    end

    describe "when the workdir has spec dir modifications" do
      before(:each) do
        thinrepo.clone(remote, {:ref => ref})
        FileUtils.mkdir_p(File.join(thinrepo.path, 'spec'))
        File.open(File.join(thinrepo.path, 'spec', 'file_spec.rb'), 'a') { |f| f.write('local modifications!') }
        thinrepo.stage_files(['spec/file_spec.rb'])
      end
      it "is dirty with exclude_spec false" do
        expect(subject.status(ref, false)).to eq :dirty
      end

      it "is insync with exclude_spec true" do
        expect(subject.status(ref, true)).to eq :insync
      end
    end

    describe "if the right ref is checked out" do
      it "is insync" do
        thinrepo.clone(remote, {:ref => ref})
        expect(subject.status(ref)).to eq :insync
      end
    end
  end

  describe "syncing" do
    describe "when the ref is unresolvable" do
      let(:ref) { '1.1.x' }

      it "raises an error" do
        expect {
          subject.sync(ref)
        }.to raise_error(R10K::Git::UnresolvableRefError)
      end
    end

    describe "when the repo is absent" do
      it "creates the repo" do
        subject.sync(ref)
        expect(subject.status(ref)).to eq :insync
      end
    end

    describe "when the repo is mismatched" do
      it "removes and recreates the repo" do
        thinrepo.path.mkdir
        subject.sync(ref)
        expect(subject.status(ref)).to eq :insync
      end
    end

    describe "when the repo is out of date" do
      it "updates the repository" do
        thinrepo.clone(remote, {:ref => '1.0.0'})
        subject.sync(ref)
        expect(subject.status(ref)).to eq :insync
      end
    end

    describe "when the workdir is dirty" do
      before(:each) do
        thinrepo.clone(remote, {:ref => ref})
        File.open(File.join(thinrepo.path, 'README.markdown'), 'a') { |f| f.write('local modifications!') }
      end

      context "when force == true" do
        let(:force) { true }

        it "warns and overwrites local modifications" do
          expect(subject.logger).to receive(:warn).with(/overwriting local modifications/i)

          subject.sync(ref, force)

          expect(subject.status(ref)).to eq :insync
        end
      end

      context "when force != true" do
        let(:force) { false }

        it "warns and does not overwrite local modifications" do
          expect(subject.logger).to receive(:warn).with(/skipping.*due to local modifications/i)

          subject.sync(ref, force)

          expect(subject.status(ref)).to eq :dirty
        end
      end
    end
  end
end
