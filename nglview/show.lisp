(in-package :nglv)
;;;https://github.com/drmeister/spy-ipykernel/blob/master/nglview/show.py#L37

(defparameter *all* (list "demo" "show_pdbid" "show_url" "show_text" "show_ase" "show_simpletraj" "show_mdtraj" "show_pytraj" "show_mdanalysis" "show_parmed" "show_rdkit" "show_structure_file" "show_htmd"))

(defun show_pdbid (pdbid &rest kwargs &key &allow-other-keys)
  "Show PDB entry.
    Examples - (defparameter w (nglv:show_pdbid \"3pqr\"))
               (cl-jupyter-widgets::disp w)???????"
  (let ((structure (make-instance 'PdbIdStructure :pdbid pdbid)))
       (apply #'make-instance 'NGLWidget :structure structure kwargs)))

(defun show_url (url &rest kwargs &key &allow-other-keys)
  (let ((kwargs2 (copy-list kwargs)) (view (make-instance 'NGLWidget)))
    (apply #'add_component view url kwargs2)
    view))

(defun show_text (text &rest kwargs &key &allow-other-keys)
  (let ((structure (make-instance 'TextStructure text)))
    (apply #'make-instance 'NGLWidget :structure structure kwargs)))

(defun show_ase (ase_atoms &rest kwargs &key &allow-other-keys)
  (let ((structure (make-instance 'ASEStructure ase_atoms)))
    (apply #'make-instance 'NGLWidget :structure structure kwargs)))

(defun show_structure_file (path &rest kwargs &key &allow-other-keys)
  (let ((structure (make-instance 'FileStructure path)))
    (apply #'make-instance 'NGLWidget :structure structure kwargs)))

(defun show_simpletraj (traj &rest kwargs &key &allow-other-keys)
  (apply #'make-instance 'NGLWidget :traj traj kwargs))

(defun show_mdtraj (mdtraj_trajectory &rest kwargs &key &allow-other-keys)
  (let ((structure_trajectory (apply #'make-instance 'MDTrajTrajectory mdtraj_trajectory)))
    (apply (make-instance 'NGLWidget :structure_trajectory structure_trajectory kwargs))))

(defun show_pytraj (pytraj_trajectory &rest kwargs &key &allow-other-keys)
  (let ((trajlist nil))
    (if (or (typep pytraj_trajectory list) (typep pytraj_trajectory tuple))
      (setf trajlist pytraj_trajectory)
      (setf trajlist (list pytraj_trajectory)))
    (setf trajlist (loop for traj in trajlist
		      collect (make-instance 'PyTrajTrajectory :traj traj)))
    (apply #'make-instance 'NGLWidget :trajlist trajlist kwargs)))

(defun show_parmed (parmed_structure &rest kwargs &key &allow-other-keys)
  (let ((structure_trajectory (make-instance 'ParmEdTrajectory :trajectory parmed_structure)))
    (apply #'make-instance 'NGLWidget :structure structure_trajectory kwargs)))

(defun show_rdkit (rdkit_mol &rest kwargs &key &allow-other-keys)
  (error "show::show_rdkit error!!! Implement me!!!!"))
#|
def show_rdkit(rdkit_mol, **kwargs):
    '''Show rdkit's Mol.

    Parameters
    ----------
    rdkit_mol : rdkit.Chem.rdchem.Mol
    kwargs : additional keyword argument

    Examples
    --------
    >>> import nglview as nv
    >>> from rdkit import Chem
    >>> from rdkit.Chem import AllChem
    >>> m = Chem.AddHs(Chem.MolFromSmiles('COc1ccc2[C@H](O)[C@@H](COc2c1)N3CCC(O)(CC3)c4ccc(F)cc4'))
    >>> AllChem.EmbedMultipleConfs(m, useExpTorsionAnglePrefs=True, useBasicKnowledge=True)
    >>> view = nv.show_rdkit(m)
    >>> view

    >>> # add component m2
    >>> # create file-like object
    >>> fh = StringIO(Chem.MolToPDBBlock(m2))
    >>> view.add_component(fh, ext='pdb')

    >>> # load as trajectory, need to have ParmEd
    >>> view = nv.show_rdkit(m, parmed=True)
    '''
    from rdkit import Chem
    fh = StringIO(Chem.MolToPDBBlock(rdkit_mol))

    try:
        use_parmed = kwargs.pop("parmed")
    except KeyError:
        use_parmed = False

    if not use_parmed:
        view = NGLWidget()
        view.add_component(fh, ext='pdb', **kwargs)
        return view
    else:
        import parmed as pmd
        parm = pmd.load_rdkit(rdkit_mol)
        parm_nv = ParmEdTrajectory(parm)

        # set option for ParmEd
        parm_nv.only_save_1st_model = False

        # set option for NGL
        # wait for: https://github.com/arose/ngl/issues/126
        # to be fixed in NGLView
        # parm_nv.params = dict(firstModelOnly=True)
        return NGLWidget(parm_nv, **kwargs)
|#

(defun show_mdanalysis (atomgroup &rest kwargs &key &allow-other-keys)
  (let ((structure_trajectory (make-instance 'MDAnalysisTrajectory :atomgroup atomgroup)))
    (apply #'make-instance 'NGLWidget :structure structure_trajectory kwargs)))

(defun show_htmd (mol &rest kwargs &key &allow-other-keys)
  (let ((structure_trajectory (make-instance 'HTMDTrajectory :mol mol)))
    (apply #'make-instance 'NGLWidget :structure structure_trajectory kwargs)))

(defun demo (&rest kwargs &key &allow-other-keys)
  (show_structure_file datafiles.PDB kwargs))
;;I don't really know if this is correct but in the demo they just do demo() so there are no args so like do i need the *args part?? I'm thinkin no so let's wing it.
#|
def demo(*args, **kwargs):
    from nglview import show_structure_file
    return show_structure_file(datafiles.PDB, *args, **kwargs)
|#