
sed "s|gs|unocc|g" inp_gs > inp
cat kpts >> inp
mpirun  ~/Codes/Sources/octopus-metric/parallel/src/main/octopus
